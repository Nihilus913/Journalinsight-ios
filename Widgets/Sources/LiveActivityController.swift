import ActivityKit
import Foundation
import JISnapshot

/// ActivityKit's `Activity<T>` is a reference type documented as safe to
/// drive from any thread (that's the whole point of its async `update`/`end`
/// API), but the class itself declares no `Sendable` conformance, and its
/// async methods predate Swift 6's actor-isolation-by-default — so calling
/// them from a `Task` off `@MainActor` storage trips the region-isolation
/// "sending risks a data race" check on the class's lack of `Sendable`, not
/// on any actual unsafety. This box asserts that documented safety contract
/// once, at the one call site that needs it, instead of disabling isolation
/// checking more broadly.
private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    // `nonisolated(unsafe)`, not a plain `let`: a struct/`let` still makes the
    // region-isolation checker descend into `Value`'s own (non-)Sendability
    // when the box crosses into a detached `Task`, even though the box type
    // itself is `@unchecked Sendable` — defeating the point of the box. The
    // class + `nonisolated(unsafe)` combination is what actually opts the
    // stored value out of that check, per the same reasoning as `activity`
    // above and `SnapshotStore.defaults`.
    nonisolated(unsafe) let value: Value
    init(value: Value) { self.value = value }
}

/// ActivityKit attributes for the verdict Live Activity. Local-start only
/// (no push-to-start / APNs this wave — see plan risk register).
///
/// `nonisolated` because `Activity<T>.request`/`.update`/`.end` run off the
/// main actor internally; the Widgets target defaults new declarations to
/// `@MainActor` (project.yml `SWIFT_DEFAULT_ACTOR_ISOLATION`), which would
/// otherwise make this conformance unusable from that @concurrent context.
public nonisolated struct VerdictActivityAttributes: ActivityAttributes {
    public nonisolated struct ContentState: Codable, Hashable, Sendable {
        public var verdictWord: String
        public var verdictSession: String
        public var verdictTone: String
        public var readiness: Double?
        public var lastUpdate: Date

        public init(verdictWord: String, verdictSession: String, verdictTone: String, readiness: Double?, lastUpdate: Date) {
            self.verdictWord = verdictWord
            self.verdictSession = verdictSession
            self.verdictTone = verdictTone
            self.readiness = readiness
            self.lastUpdate = lastUpdate
        }
    }

    public init() {}
}

/// Owns the single verdict Live Activity's lifecycle: local start, update on
/// a new `HubSnapshot`, and auto-end per `LiveActivityCapPolicy`.
///
/// Frozen API (CONTEXT-IOS-FOUNDATION change rule applies): `shared`,
/// `update(from:)`, `end()`. W2c-L1 (`AppEnvironment`) codes against this
/// signature; do not rename without a note here in the same commit.
@MainActor
public final class LiveActivityController {
    public static let shared = LiveActivityController()

    // `Activity<T>` is a reference type ActivityKit itself designs for
    // concurrent use (its own `update`/`end` are `@concurrent` async), but
    // storing it as a plain MainActor-isolated `var` makes the region-isolation
    // checker flag every `Task { await activity.update(...) }` as a data-race
    // risk (the same storage remains reachable from `self` after the value is
    // "sent"). `nonisolated(unsafe)` mirrors `SnapshotStore.defaults`'s pattern
    // for the same reason: this type's own contract, not Swift's inference,
    // is what makes concurrent access safe here, and every read/write in this
    // file still only happens from `@MainActor` methods.
    private nonisolated(unsafe) var activity: Activity<VerdictActivityAttributes>?
    private var startedAt: Date?
    private var lastUpdateAt: Date?
    private let now: () -> Date

    /// `now` is a test seam only — production always uses `Date.init`.
    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Starts the activity on the first call, or refreshes its content
    /// state on subsequent calls. Ends and restarts if the running activity
    /// has already crossed the auto-end cap (belt-and-suspenders alongside
    /// the explicit `end()` callers are expected to make).
    public func update(from snapshot: HubSnapshot) {
        let moment = now()

        if let startedAt, let lastUpdateAt,
           LiveActivityCapPolicy.shouldEnd(startedAt: startedAt, lastUpdateAt: lastUpdateAt, now: moment) {
            end()
        }

        let state = VerdictActivityAttributes.ContentState(
            verdictWord: snapshot.verdictWord,
            verdictSession: snapshot.verdictSession,
            verdictTone: snapshot.verdictTone,
            readiness: snapshot.readiness,
            lastUpdate: moment
        )
        let content = ActivityContent(state: state, staleDate: moment.addingTimeInterval(LiveActivityCapPolicy.staleCap))

        if let activity {
            let box = UncheckedSendableBox(value: activity)
            // `.detached`, not a plain `Task { }`: a plain Task inherits the
            // caller's actor (MainActor) under NonisolatedNonsendingByDefault,
            // which would still cross into ActivityKit's off-actor `update`
            // from MainActor and re-trip the same "sending" check the box
            // exists to avoid. Detaching puts the closure itself off-actor
            // first, so the call into `update` no longer crosses isolation.
            Task.detached { await box.value.update(content) }
            lastUpdateAt = moment
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                let newActivity = try Activity.request(attributes: VerdictActivityAttributes(), content: content)
                activity = newActivity
                startedAt = moment
                lastUpdateAt = moment
            } catch {
                // Live Activities unavailable (disabled, over budget, etc.) — no-op, never crash.
            }
        }
    }

    /// Ends the running activity immediately, if any. Safe to call when
    /// there is no active activity.
    public func end() {
        guard let activity else { return }
        let box = UncheckedSendableBox(value: activity)
        Task.detached { await box.value.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
        startedAt = nil
        lastUpdateAt = nil
    }
}

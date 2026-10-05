import Foundation
import Observation
import JICore
import JIPersistence

/// W-B91 (Toby 2026-10-04: "B91 pause should be a manual status") — Settings' "I'm on a break"
/// toggle. The hub holds the state (`GET/PUT /api/v1/planning/training-break`); Decide's Load row
/// reads "Paused" + the start date from the hub's `/morning` while it is on.
///
/// B-52 p4: offline-first. A flip is queued as outbox kind `training_break` (last-write-wins) and
/// shown at once, marked pending ("Saved on this phone"); the drainer sends it when the hub is
/// back. Only a hub REFUSAL (4xx) reverts the toggle, with the hub's reason.
@Observable @MainActor
public final class TrainingBreakViewModel {
    public private(set) var state: TrainingBreak?
    public private(set) var busy = false
    public private(set) var errorMessage: String?
    /// B-52 p2: when the last read came from the offline cache (hub unreachable), the fetch time of
    /// that copy — the row shows the last-known state with an "Offline — showing data from …" line
    /// instead of an empty, disabled toggle. nil = the hub answered.
    public private(set) var staleSince: Date?
    /// B-52 p4: a flip is queued on this phone and not yet on the hub.
    public private(set) var pending = false

    private let provider: any TrainingBreakProviding
    private let outbox: Outbox?
    private let drainer: OutboxDrainer?
    private let now: () -> Date

    /// B-107: runs after every confirmed write (the app shell re-fetches Today/Decide so the Load
    /// row reads "Paused" at once, not after a relaunch). Never runs on a failed write.
    @ObservationIgnored public var onChanged: (@MainActor () async -> Void)?

    /// `outbox` nil (previews, fixtures) = a throwaway in-memory queue: the write path is the
    /// same OutboxFirst path either way — there is no direct hub write in this model.
    public init(provider: any TrainingBreakProviding, state: TrainingBreak? = nil, outbox: Outbox? = nil,
                now: @escaping () -> Date = Date.init,
                onChanged: (@MainActor () async -> Void)? = nil) {
        self.provider = provider
        self.state = state
        self.onChanged = onChanged
        self.now = now
        let queue = outbox ?? (try? AppDatabase.inMemory()).map { Outbox(db: $0) }
        self.outbox = queue
        let handler = B52WriteKinds.trainingBreakHandler(provider: { provider })
        self.drainer = queue.map { B52WriteKinds.localDrainer(outbox: $0, handler: handler) }
        applyPending()
    }

    /// "Saved on this phone — …" while a flip is queued; nil otherwise.
    public var pendingText: String? {
        pending ? "Saved on this phone — syncs when the hub is reachable" : nil
    }

    public var paused: Bool { state?.paused == true }

    /// "On a break since 28 Sep" while paused; nil otherwise.
    public var sinceText: String? {
        guard paused, let since = state?.since else { return nil }
        return "On a break since \(trainingBreakDayText(since))"
    }

    /// B-52 p2: reads through the hub's offline cache — offline with a stored copy = that state +
    /// `staleSince`; offline with a cold cache = the explicit error (no fabricated "off").
    public func load() async {
        let provider = self.provider
        do {
            let (value, since) = try await HubReadTrace.collect { try await provider.trainingBreak() }
            state = value; staleSince = since; errorMessage = nil
        } catch {
            errorMessage = state == nil ? "Hub unreachable — the break can't be read right now" : nil
        }
        applyPending()
    }

    /// "Offline — showing data from 07:41" while the shown state is the cached copy.
    public var offlineText: String? { staleSince.map { offlineReadCaption(since: $0) } }

    /// A queued flip wins over the hub's (or the cache's) older answer until it is delivered.
    private func applyPending() {
        if let queued = B52WriteKinds.newestPending(B52WriteKinds.trainingBreak, in: outbox, as: TrainingBreak.self) {
            state = queued
            pending = true
            errorMessage = nil
        } else {
            pending = false
        }
    }

    /// On = a break from `since` (nil = the phone's today, stamped at the tap so a replay days
    /// later still starts the break on the day it was set); off = the break ends (hub's today).
    public func set(paused: Bool, since: String? = nil) async {
        guard let outbox else { errorMessage = "Could not update the break — couldn't save it on this phone"; return }
        busy = true
        defer { busy = false }
        let previous = state, wasPending = pending
        let body = TrainingBreak(paused: paused, since: paused ? (since ?? B52WriteKinds.localDay(now())) : nil)
        state = body          // shown at once; marked pending until the hub has it
        pending = true
        errorMessage = nil
        let outcome = await OutboxFirst(outbox: outbox, drainer: drainer)
            .submit(kind: B52WriteKinds.trainingBreak, payload: body)
        switch outcome {
        case .delivered:
            pending = false
            staleSince = nil
            if let confirmed = try? await provider.trainingBreak() { state = confirmed }
            applyPending()
            await onChanged?()
        case .queued:
            applyPending()
        case .rejected(let reason):
            state = previous; pending = wasPending
            errorMessage = "Could not update the break — \(reason)"
            applyPending()
        case .notQueued(let reason):
            state = previous; pending = wasPending
            errorMessage = "Could not update the break — \(reason)"
        }
    }
}

nonisolated func trainingBreakErrorText(_ error: Error) -> String {
    switch error as? HubError {
    case .network?: return "hub unreachable"
    case .http(_, let detail?)?: return detail
    default: return "the hub said no"
    }
}

/// "2026-09-28" → "28 Sep" (the hub caption's spelling); unparseable input is returned as is.
public nonisolated func trainingBreakDayText(_ iso: String) -> String {
    let parts = iso.split(separator: "-")
    guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return iso }
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(d) \(months[m - 1])"
}

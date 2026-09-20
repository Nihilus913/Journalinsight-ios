import Foundation
import JICore
import JIPersistence

/// What one drained `Outbox` row delivered — one case per outbox `kind` the drainer knows how to
/// replay. A caller that enqueued a row of a specific kind (e.g. `WeighInViewModel`) pattern-matches
/// the case it expects; the retry paths (`drainOnForeground`, `OutboxRetryScheduler`) only count.
public nonisolated enum OutboxDelivery: Sendable, Equatable {
    case weighIn(WeighinResult)
    case gateRespond(GateRespondResult)
    case sessionFeel(FeelResult)
}

/// Drains `Outbox` rows against the hub, one attempt per row per call, for every kind the app
/// enqueues (W8-L4, P-weigh-in + P-hub-watchdog): `"weighin"` (W3b `WeighInViewModel`) plus W5b's
/// `"gateRespond"` / `"sessionFeel"` rows (`GateRespondViewModel`), which until this wave nothing
/// drained once their first in-tap attempt failed. Lives in `Shared/` because it is no longer a
/// weigh-in-only component.
///
/// Kind → provider: a row is attempted only when a provider for its kind was injected; a row of a
/// kind this drainer has no provider for (or one it doesn't know) is left untouched — never
/// silently dropped. `WeighInViewModel.submit` calls `drainOnce()` right after enqueuing so a
/// reachable hub confirms in the same beat the user tapped Save; `HubWatchdog.onReachableAgain`
/// and `OutboxRetryScheduler` call it again later for anything still pending.
@MainActor
public final class OutboxDrainer {
    private let outbox: Outbox
    private let weighIn: (any WeighInProviding)?
    private let gateRespond: (any GateRespondProviding)?

    /// W9.5-L1 (scout S1-1): the ONE pass currently awaiting the hub, or `nil`. `drainOnce()` is
    /// reachable from three places that can overlap in time — `WeighInViewModel.submit` (in-tap),
    /// `HubWatchdog.onReachableAgain` (`drainOnForeground`) and `OutboxRetryScheduler`'s
    /// foreground tick / BG refresh. Without this, each of them re-read `pending()` while an
    /// earlier pass was still mid-POST and sent the same row again (double weigh-in / double
    /// gate-respond). An overlapping caller now awaits and returns THIS task's result instead of
    /// starting its own pass; the guard is per-pass, not sticky (cleared before the task returns).
    private var inFlight: Task<[Int64: Result<OutboxDelivery, Error>], Never>?

    /// The multi-kind initialiser. Pass `nil` for a kind this app instance cannot deliver (e.g.
    /// `MockDataProvider` in previews) — its rows then stay pending rather than being attempted
    /// against nothing.
    public init(outbox: Outbox, weighIn: (any WeighInProviding)?, gateRespond: (any GateRespondProviding)?) {
        self.outbox = outbox
        self.weighIn = weighIn
        self.gateRespond = gateRespond
    }

    /// W3b shape, kept so `WeighInViewModel` and the watchdog wiring compile unchanged: a drainer
    /// over ONE `WeighInProviding` handles weigh-in rows only.
    public convenience init(outbox: Outbox, provider: any WeighInProviding) {
        self.init(outbox: outbox, weighIn: provider, gateRespond: provider as? any GateRespondProviding)
    }

    /// One hub object serving every kind it conforms to (`HubDataProvider` conforms to both).
    public convenience init(outbox: Outbox, hub: any Sendable) {
        self.init(outbox: outbox, weighIn: hub as? any WeighInProviding, gateRespond: hub as? any GateRespondProviding)
    }

    public nonisolated static let weighInKind = "weighin"
    public nonisolated static let gateRespondKind = GateRespondViewModel.gateRespondKind
    public nonisolated static let sessionFeelKind = GateRespondViewModel.sessionFeelKind
    public nonisolated static let knownKinds: Set<String> = [weighInKind, gateRespondKind, sessionFeelKind]

    /// The kinds THIS instance can attempt (a kind whose provider is `nil` is excluded).
    public var drainableKinds: Set<String> {
        var kinds = Set<String>()
        if weighIn != nil { kinds.insert(Self.weighInKind) }
        if gateRespond != nil { kinds.insert(Self.gateRespondKind); kinds.insert(Self.sessionFeelKind) }
        return kinds
    }

    /// Pending rows of a kind this drainer can attempt — what `OutboxRetryScheduler` decides its
    /// backoff on. Rows of other kinds are not this drainer's to count.
    public func pendingDeliverableCount() -> Int {
        let kinds = drainableKinds
        return ((try? outbox.pending()) ?? []).filter { kinds.contains($0.kind) }.count
    }

    /// Attempts every pending row of a drainable kind once, oldest first. A row whose payload isn't
    /// valid JSON for its kind is left alone (never silently dropped) — it simply produces no
    /// result this pass. Success retires the row (`Outbox.markSent`); failure bumps `attempts` and
    /// records the kind's own `describe` text as `lastError` — for a hub rejection (e.g. 502) that
    /// IS the server's own `detail`, verbatim (PINNED weigh-in contract: `describeWeighinError` in
    /// the RN oracle's `useLogFoodActions.ts`; gate rows: `GateRespondViewModel.describe`).
    ///
    /// Serialised: a call that lands while a pass is in flight does NOT re-read `pending()` — it
    /// awaits the in-flight pass and returns its result (so a row is never POSTed twice by two
    /// overlapping triggers). Anything enqueued during that pass is picked up by the next call.
    @discardableResult
    public func drainOnce() async -> [Int64: Result<OutboxDelivery, Error>] {
        if let inFlight { return await inFlight.value }
        let pass = Task { @MainActor [self] in
            // Cleared on the actor, synchronously before the task's value is published: no window
            // in which a third caller could see a finished task and skip a row enqueued since.
            defer { self.inFlight = nil }
            return await self.drainPass()
        }
        inFlight = pass
        return await pass.value
    }

    /// One unguarded pass over every pending row of a drainable kind — only ever run through
    /// `drainOnce()`'s `inFlight` task.
    private func drainPass() async -> [Int64: Result<OutboxDelivery, Error>] {
        var results: [Int64: Result<OutboxDelivery, Error>] = [:]
        guard let rows = try? outbox.pending() else { return results }
        for row in rows {
            // Plain `JSONDecoder()`, matching `Outbox.enqueue`'s plain `JSONEncoder()` — see its
            // doc comment (this is the outbox's own storage format, not a hub wire body).
            switch row.kind {
            case Self.weighInKind:
                guard let weighIn, let body = try? JSONDecoder().decode(WeighinBody.self, from: row.payload) else { continue }
                await attempt(row: row, describe: Self.describe, into: &results) {
                    .weighIn(try await weighIn.logWeighin(weightKg: body.weightKg, date: body.date))
                }
            case Self.gateRespondKind:
                guard let gateRespond, let body = try? JSONDecoder().decode(GateRespondBody.self, from: row.payload) else { continue }
                await attempt(row: row, describe: GateRespondViewModel.describe, into: &results) {
                    .gateRespond(try await gateRespond.respondGate(choice: body.choice, overrideReason: body.overrideReason, windowDays: body.windowDays))
                }
            case Self.sessionFeelKind:
                guard let gateRespond, let body = try? JSONDecoder().decode(FeelBody.self, from: row.payload) else { continue }
                await attempt(row: row, describe: GateRespondViewModel.describe, into: &results) {
                    .sessionFeel(try await gateRespond.logFeel(feelScore: body.feelScore, notes: body.notes, date: body.date))
                }
            default:
                continue
            }
        }
        return results
    }

    private func attempt(
        row: OutboxRow,
        describe: (Error) -> String,
        into results: inout [Int64: Result<OutboxDelivery, Error>],
        _ send: () async throws -> OutboxDelivery
    ) async {
        do {
            let delivery = try await send()
            try? outbox.markSent(id: row.id)
            results[row.id] = .success(delivery)
        } catch {
            try? outbox.markFailed(id: row.id, error: describe(error))
            results[row.id] = .failure(error)
        }
    }

    /// W7-L4 (P-hub-watchdog): the pass `HubWatchdog.onReachableAgain` runs on its false → true
    /// transition — the moment the hub answered `/health` again (typically right after a
    /// foreground) is when a row queued while the Mac was asleep should finally go out. One
    /// transition, one pass over every drainable kind; a row that fails again simply stays pending
    /// with its `attempts` bumped. Periodic retry with backoff and the BG-refresh path are
    /// `OutboxRetryScheduler` (W8-L4), which calls `drainOnce()` the same way.
    @discardableResult
    public func drainOnForeground() async -> [Int64: Result<OutboxDelivery, Error>] {
        await drainOnce()
    }

    /// The hub's own `detail` verbatim for a named `HubError` that carries one (502 decodes as
    /// `.yazioAuthExpired` regardless of which endpoint raised it — see `HubError.from`); a
    /// generic retry line otherwise. Mirrors `describeWeighinError` in the RN oracle.
    public nonisolated static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .yazioAuthExpired(let detail) where !detail.isEmpty: detail
        case .http(_, let detail) where detail?.isEmpty == false: detail!
        case .network(let message): message
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        default: "Couldn't save weigh-in — try again."
        }
    }
}

public extension OutboxDelivery {
    /// Convenience for the one caller that enqueued a weigh-in and wants its confirmation back.
    var weighInResult: WeighinResult? { if case .weighIn(let r) = self { r } else { nil } }
}

import Foundation
import JICore
import JIPersistence

/// Drains `"weighin"` rows off `Outbox` against a `WeighInProviding` hub, one attempt per row per
/// call (W3b-L4, P-weigh-in). `WeighInViewModel.submit` calls `drainOnce()` right after enqueuing,
/// so a reachable hub confirms in the same beat the user tapped Save; a later retry pass (app
/// foreground, background task — not this wave's scope) can call `drainOnce()` again for anything
/// still pending.
@MainActor
public final class OutboxDrainer {
    private let outbox: Outbox
    private let provider: any WeighInProviding

    public init(outbox: Outbox, provider: any WeighInProviding) {
        self.outbox = outbox
        self.provider = provider
    }

    /// Attempts every pending `"weighin"` row once, oldest first. A row that isn't valid
    /// `WeighinBody` JSON is left alone (never silently dropped) — it simply produces no result
    /// this pass. Success retires the row (`Outbox.markSent`); failure bumps `attempts` and
    /// records `describe(error)` as `lastError` — for a hub rejection (e.g. 502) that IS the
    /// server's own `detail`, verbatim (PINNED weigh-in contract: `describeWeighinError` in the RN
    /// oracle's `useLogFoodActions.ts`).
    @discardableResult
    public func drainOnce() async -> [Int64: Result<WeighinResult, Error>] {
        var results: [Int64: Result<WeighinResult, Error>] = [:]
        guard let rows = try? outbox.pending() else { return results }
        for row in rows where row.kind == Self.weighInKind {
            // Plain `JSONDecoder()`, matching `Outbox.enqueue`'s plain `JSONEncoder()` — see its
            // doc comment (this is the outbox's own storage format, not a hub wire body).
            guard let body = try? JSONDecoder().decode(WeighinBody.self, from: row.payload) else { continue }
            do {
                let result = try await provider.logWeighin(weightKg: body.weightKg, date: body.date)
                try? outbox.markSent(id: row.id)
                results[row.id] = .success(result)
            } catch {
                try? outbox.markFailed(id: row.id, error: Self.describe(error))
                results[row.id] = .failure(error)
            }
        }
        return results
    }

    /// W7-L4 (P-hub-watchdog): the "later retry pass" `drainOnce`'s doc comment deferred, scoped to
    /// exactly ONE trigger — `HubWatchdog`'s false → true transition, which the app hooks via
    /// `onReachableAgain`. That moment (hub answered `/health` again, typically right after a
    /// foreground) is when a weigh-in queued while the Mac was asleep should finally go out.
    ///
    /// Deliberately not a periodic retry and not a background task: a timer that hammers an
    /// unreachable hub buys nothing the watchdog's own probe doesn't already tell us, and periodic
    /// retry is its own BACKLOG row. One transition, one pass — a row that fails again simply stays
    /// pending with its `attempts` bumped, exactly as `drainOnce` already records it.
    @discardableResult
    public func drainOnForeground() async -> [Int64: Result<WeighinResult, Error>] {
        await drainOnce()
    }

    public nonisolated static let weighInKind = "weighin"

    /// The hub's own `detail` verbatim for a named `HubError` that carries one (502 decodes as
    /// `.yazioAuthExpired` regardless of which endpoint raised it — see `HubError.from`); a
    /// generic retry line otherwise. Mirrors `describeWeighinError` in the RN oracle.
    public static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .yazioAuthExpired(let detail) where !detail.isEmpty: detail
        case .http(_, let detail) where detail?.isEmpty == false: detail!
        case .network(let message): message
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        default: "Couldn't save weigh-in — try again."
        }
    }
}

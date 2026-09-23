import Foundation
import Observation
import JICore
import JIPersistence

/// W-B57b (B-62) — Decide's Go / Adjust write: the user's call on the MORNING training verdict
/// (`POST /api/v1/planning/verdict-override`), never the weekly gate (`respondGate`).
///
/// Outbox-first in exactly `GateRespondViewModel.respond`'s order: the row is enqueued FIRST (so
/// the answer survives going offline or the app being killed), THEN posted, and a confirmed POST
/// mirrors the hub's row into `current`. A network failure leaves the row pending and settles as
/// `.queued` with an optimistic `current`; any other hub rejection is `.failed` with the hub's own
/// `detail`, and `current` keeps its previous value. The screen advances only on `settled`.
@Observable @MainActor
public final class VerdictOverrideViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case submitting
        /// The hub confirmed; `current` is its row.
        case logged
        /// Enqueued but not confirmed (hub unreachable) — stays in the outbox for a later drain.
        case queued
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    /// The override in effect for the verdict date, as far as this device knows.
    public private(set) var current: VerdictOverride?

    public var errorMessage: String? { if case .failed(let message) = phase { message } else { nil } }
    /// `.logged` or `.queued` — the only states Decide may advance on.
    public var settled: Bool { phase == .logged || phase == .queued }

    public nonisolated static let verdictOverrideKind = "verdictOverride"
    public nonisolated static let verdictOverrideClearKind = "verdictOverrideClear"

    private let provider: any VerdictOverrideProviding
    private let outbox: Outbox
    private let now: @Sendable () -> Date

    /// `current` seeds from `MorningResponse.verdictOverride` so a relaunch shows the stored call.
    public init(
        provider: any VerdictOverrideProviding,
        outbox: Outbox,
        current: VerdictOverride? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.outbox = outbox
        self.current = current
        self.now = now
    }

    /// Re-seed from a fresher `/morning` (does not touch `phase`).
    public func seed(_ override: VerdictOverride?) { current = override }

    /// Go = `.accept`; Adjust = `.full` / `.modified` / `.rest` + a reason. `optimisticSession` is
    /// what `current.session` shows while the row is only queued (see `localOverrideSession`).
    @discardableResult
    public func setOverride(date: String, choice: VerdictOverrideChoice, reason: String = "", optimisticSession: String? = nil) async -> Bool {
        phase = .submitting
        let body = VerdictOverrideBody(date: date, choice: choice, reason: reason)
        retirePending(date: date)
        let queuedId: Int64
        do {
            queuedId = try outbox.enqueue(kind: Self.verdictOverrideKind, payload: body, now: now())
        } catch {
            phase = .failed("Couldn't save your call — try again.")
            return false
        }
        do {
            let result = try await provider.setVerdictOverride(date: date, choice: choice, reason: reason)
            try? outbox.markSent(id: queuedId)
            current = result
            phase = .logged
            return true
        } catch {
            try? outbox.markFailed(id: queuedId, error: Self.describe(error))
            if case HubError.network = error {
                current = VerdictOverride(date: date, choice: choice, reason: reason.isEmpty ? nil : reason,
                                          session: optimisticSession ?? "", createdAt: nil)
                phase = .queued
                return true
            }
            phase = .failed(Self.describe(error))
            return false
        }
    }

    /// Undo (`DELETE …/verdict-override?date=`), same outbox-first order. A still-queued set for
    /// that date is retired first so a later drain can never re-apply it; a 404 means the hub
    /// already has none — treated as cleared.
    @discardableResult
    public func clear(date: String) async -> Bool {
        phase = .submitting
        retirePending(date: date)
        let queuedId: Int64
        do {
            queuedId = try outbox.enqueue(kind: Self.verdictOverrideClearKind, payload: VerdictOverrideClearBody(date: date), now: now())
        } catch {
            phase = .failed("Couldn't undo — try again.")
            return false
        }
        do {
            try await provider.clearVerdictOverride(date: date)
        } catch HubError.http(status: 404, detail: _) {
            // Nothing stored for that date — the undo already holds.
        } catch {
            try? outbox.markFailed(id: queuedId, error: Self.describe(error))
            if case HubError.network = error {
                if current?.date == date { current = nil }
                phase = .idle
                return true
            }
            phase = .failed(Self.describe(error))
            return false
        }
        try? outbox.markSent(id: queuedId)
        if current?.date == date { current = nil }
        phase = .idle
        return true
    }

    /// Pending set/clear rows for `date` are superseded by the call being made now.
    private func retirePending(date: String) {
        guard let rows = try? outbox.pending() else { return }
        for row in rows {
            let rowDate: String? = switch row.kind {
            case Self.verdictOverrideKind: (try? JSONDecoder().decode(VerdictOverrideBody.self, from: row.payload))?.date
            case Self.verdictOverrideClearKind: (try? JSONDecoder().decode(VerdictOverrideClearBody.self, from: row.payload))?.date
            default: nil
            }
            if rowDate == date { try? outbox.markSent(id: row.id) }
        }
    }

    /// The hub's own `detail` where it gave one; same convention as `GateRespondViewModel.describe`.
    public nonisolated static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .http(_, let detail) where detail?.isEmpty == false: detail!
        case .duplicate(let detail) where !detail.isEmpty: detail
        case .yazioAuthExpired(let detail) where !detail.isEmpty: detail
        case .network(let message): message
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        default: "Couldn't save your call — try again."
        }
    }
}

import Foundation
import Observation
import JICore
import JIPersistence

/// W3b-L4 (P-weigh-in), mirrors `mobile/src/data/useLogFoodActions.ts`'s `useLogWeighin` +
/// `describeWeighinError`, offline-first via `Outbox`: `submit` enqueues the write BEFORE any
/// network attempt (survives the app going offline or being killed mid-request), then drains it
/// once immediately so a reachable hub confirms in the same tap. CLAUDE.md rule 5: the sheet must
/// never show a zero weight — `submit` only ever receives an already-validated, positive `weightKg`
/// (the view's own guard); this type never substitutes a `0` default of its own.
@Observable @MainActor
public final class WeighInViewModel {
    public enum SubmitState: Equatable, Sendable {
        case idle
        case submitting
        /// Confirmed by the hub, Garmin write verified.
        case success(WeighinResult)
        /// Enqueued but not yet confirmed (hub unreachable) — the row stays in the outbox for a
        /// later retry; this is not a failure the user needs to act on.
        case queued
        case failure(String)
    }

    public private(set) var state: SubmitState = .idle
    private let outbox: Outbox
    private let drainer: OutboxDrainer

    public init(outbox: Outbox, provider: any WeighInProviding) {
        self.outbox = outbox
        self.drainer = OutboxDrainer(outbox: outbox, provider: provider)
    }

    /// Test seam: inject a drainer directly (e.g. one built over a fake provider).
    init(outbox: Outbox, drainer: OutboxDrainer) {
        self.outbox = outbox
        self.drainer = drainer
    }

    @discardableResult
    public func submit(weightKg: Double, date: String? = nil) async -> Bool {
        state = .submitting
        let id: Int64
        do {
            id = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: weightKg, date: date))
        } catch {
            state = .failure("Couldn't save weigh-in — try again.")
            return false
        }
        let results = await drainer.drainOnce()
        switch results[id] {
        case .success(let result):
            state = .success(result)
            return true
        case .failure(let error):
            if case HubError.network = error {
                state = .queued
                return true
            }
            state = .failure(OutboxDrainer.describe(error))
            return false
        case nil:
            // Row wasn't attempted this pass (shouldn't happen right after enqueue, but never
            // treat "no result" as a failure — it's still safely queued).
            state = .queued
            return true
        }
    }
}

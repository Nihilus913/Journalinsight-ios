import Foundation
import JICore
import JIPersistence

// TEMP bridge until B-50: hub weekly gate
/// B-73: one-way copy of the user's nutrition goals to `PUT /api/v1/planning/goals`, so the hub's
/// weekly gate reads the same kcal target until the hub is retired (B-50). The phone's PrefStore
/// is the source of truth. Called ONLY from `GoalsSetupViewModel.saveNutrition` (a user save):
/// never on foreground, never on a band recompute, so there is no PUT storm (Review Focus 4).
/// Outbox-first: the row is durable before any network call. Delete this file with B-50.
@MainActor
public final class GoalsMirror {
    private let outbox: Outbox
    private let drainer: OutboxDrainer?

    public init(outbox: Outbox, drainer: OutboxDrainer?) {
        self.outbox = outbox; self.drainer = drainer
    }

    /// The PUT body: only what the user set. Unset fields are omitted (the hub keeps its value).
    /// nil when nothing is set, so nothing is queued.
    public nonisolated static func patch(for goals: MacroGoals) -> GoalsUpdate? {
        guard !goals.isUnset else { return nil }
        return GoalsUpdate(nutrition: .init(kcalGoal: goals.targetKcal, proteinG: goals.proteinG,
                                            carbsG: goals.carbsG, fatG: goals.fatG))
    }

    /// Queues the patch, then tries once. Returns the hub's document when that attempt landed,
    /// nil when it is still queued (offline), nothing was set, or no drainer exists (preview/mock).
    @discardableResult
    public func push(_ goals: MacroGoals) async -> Goals? {
        guard let patch = Self.patch(for: goals),
              let id = try? outbox.enqueue(kind: OutboxDrainer.goalsKind, payload: patch) else { return nil }
        guard let drainer else { return nil }
        let results = await drainer.drainOnce()
        if case .success(.goals(let server)) = results[id] { return server }
        return nil
    }
}

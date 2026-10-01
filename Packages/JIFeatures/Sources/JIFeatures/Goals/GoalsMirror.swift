import Foundation
import JICore
import JIPersistence

// TEMP bridge until B-50: hub weekly gate
/// B-73: copies the user's nutrition goals to the hub so its weekly gate reads the same kcal target
/// until the hub is retired (B-50). The phone's PrefStore is the source of truth. Called ONLY from
/// `GoalsSetupViewModel.saveNutrition` (a user save): never on foreground, never on a band
/// recompute, so there is no PUT storm (Review Focus 4).
/// W-TGT L3 (L1 hand-off): the copy is the ONE targets document (`PUT /planning/targets`, outbox
/// kind `targets`, via `TargetsMirror`); `/planning/goals` is read-only on the hub now.
@MainActor
public final class GoalsMirror {
    /// W-FIX10 F10-1: GoalsSetup's weight / strength / steps save through the same document.
    public let targets: TargetsMirror

    public init(targets: TargetsMirror) { self.targets = targets }

    public convenience init(prefs: PrefStore, outbox: Outbox, drainer: OutboxDrainer?) {
        self.init(targets: TargetsMirror(prefs: prefs, outbox: outbox, drainer: drainer))
    }

    /// The nutrition part of the old goals PUT (kept for readers of the hub's goals document).
    /// nil when nothing is set.
    public nonisolated static func patch(for goals: MacroGoals) -> GoalsUpdate? {
        guard !goals.isUnset else { return nil }
        return GoalsUpdate(nutrition: .init(kcalGoal: goals.targetKcal, proteinG: goals.proteinG,
                                            carbsG: goals.carbsG, fatG: goals.fatG))
    }

    /// What a save's push did. `delivered` = the hub has the document (the hub's goals document is
    /// re-read by the caller when it needs one, so this carries nil). `queued` = still in the
    /// outbox (offline / rejected). `nothingToSend` = no targets document yet: the §5 import
    /// carries the stored goals over and queues the first body itself.
    public enum PushOutcome: Equatable, Sendable {
        case delivered(Goals?)
        case queued
        case nothingToSend
    }

    @discardableResult
    public func push(_ goals: MacroGoals) async -> PushOutcome {
        guard targets.store.loadIfPresent() != nil else { return .nothingToSend }
        switch await targets.update({ $0.macroGoals = goals }) {
        case .delivered: return .delivered(nil)
        case .queued: return .queued
        }
    }
}

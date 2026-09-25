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

    /// What a save's push did. `delivered` = the hub has the row (its document when this push's
    /// own attempt landed; nil when another drainer retired the row first). `queued` = still in
    /// the outbox (offline / rejected). `nothingToSend` = nothing set, nothing queued.
    public enum PushOutcome: Equatable, Sendable {
        case delivered(Goals?)
        case queued
        case nothingToSend
    }

    /// Queues the patch, then drains until its row has an answer. fixer2 RF3-STATUS: a drain that
    /// joins a pass already in flight (started before this row was enqueued) gets that pass's
    /// results WITHOUT this row, and a second drainer instance (the retry scheduler) can retire
    /// the row under us — neither is "offline". Delivery is judged by the row itself: gone from
    /// the outbox = delivered; a failed attempt still pending = queued; no attempt yet = one more
    /// pass of our own.
    @discardableResult
    public func push(_ goals: MacroGoals) async -> PushOutcome {
        guard let patch = Self.patch(for: goals) else { return .nothingToSend }
        guard let id = try? outbox.enqueue(kind: OutboxDrainer.goalsKind, payload: patch) else { return .queued }
        guard let drainer else { return .queued }
        for _ in 0..<2 {
            let results = await drainer.drainOnce()
            if case .success(.goals(let server)) = results[id] { return .delivered(server) }
            guard isPending(id) else { return .delivered(nil) }
            if results[id] != nil { return .queued }   // attempted and failed: still queued
        }
        return .queued
    }

    private func isPending(_ id: Int64) -> Bool {
        (try? outbox.pending())?.contains { $0.id == id } ?? true
    }
}

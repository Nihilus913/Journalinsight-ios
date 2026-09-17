import Foundation
import Observation
import JIPersistence

/// W4-L3 (P-goals), mirrors `mobile/src/goals/useGoals.ts` — the local-only, ad-hoc freeform goal
/// list (`app/goals.tsx`'s oracle), backed entirely by `GoalStore`'s `goals` table (no hub call).
@Observable @MainActor
public final class GoalsViewModel {
    public private(set) var goals: [Goal] = []
    public private(set) var isLoading = true

    private let store: GoalStore

    public init(store: GoalStore) { self.store = store }

    public func load() {
        isLoading = true
        goals = (try? store.listGoals()) ?? []
        isLoading = false
    }

    public func addGoal(title: String, targetDate: String?) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        _ = try? store.addGoal(NewGoal(title: title.trimmingCharacters(in: .whitespaces), targetDate: targetDate, progress: 0))
        load()
    }

    public func setProgress(id: Int64, progress: Double) {
        try? store.setProgress(id: id, progress: progress)
        load()
    }

    public func deleteGoal(id: Int64) {
        try? store.deleteGoal(id: id)
        load()
    }
}

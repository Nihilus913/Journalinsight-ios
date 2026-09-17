import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

@Test @MainActor func goalsViewModelAddSetProgressDeleteRoundTrip() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let vm = GoalsViewModel(store: store)
    vm.load()
    #expect(vm.goals.isEmpty)

    vm.addGoal(title: "Bench 100kg", targetDate: "2026-12-31")
    #expect(vm.goals.count == 1)
    let id = vm.goals[0].id

    vm.setProgress(id: id, progress: 0.4)
    #expect(vm.goals[0].progress == 0.4)

    vm.deleteGoal(id: id)
    #expect(vm.goals.isEmpty)
}

@Test @MainActor func goalsViewModelAddGoalIgnoresBlankTitle() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let vm = GoalsViewModel(store: store)
    vm.load()
    vm.addGoal(title: "   ", targetDate: nil)
    #expect(vm.goals.isEmpty)
}

@Test @MainActor func goalsViewModelSetProgressClamps() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    let vm = GoalsViewModel(store: store)
    vm.load()
    vm.addGoal(title: "g", targetDate: nil)
    let id = vm.goals[0].id
    vm.setProgress(id: id, progress: 1.7)
    #expect(vm.goals[0].progress == 1)
}

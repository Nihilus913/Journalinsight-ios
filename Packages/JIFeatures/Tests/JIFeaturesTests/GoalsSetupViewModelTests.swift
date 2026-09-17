import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// File-local fake — mirrors `EnergyFlakyProvider`'s independence rationale (no shared
/// JIFeaturesTests support target).
nonisolated struct GoalsFakeProvider: GoalsSetupProviding {
    let inner = MockDataProvider()
    let updateFails: HubError?
    init(updateFails: HubError? = nil) { self.updateFails = updateFails }
    func energy(windowDays: Int) async throws -> EnergyReport { try await inner.energy(windowDays: windowDays) }
    func goals() async throws -> Goals { try await inner.goals() }
    func updateGoals(_ patch: GoalsUpdate) async throws -> Goals {
        if let updateFails { throw updateFails }
        return try await inner.updateGoals(patch)
    }
}

@Test @MainActor func goalsSetupLoadPopulatesGoals() async throws {
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider())
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.goals?.stepsDaily == 15000)
}

@Test @MainActor func goalsSetupSavePutsPatchAndReplacesGoalsWithServerResult() async throws {
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider())
    await vm.load()
    let ok = await vm.save(GoalsUpdate(stepsDaily: 12000))
    #expect(ok)
    #expect(vm.phase == .loaded)
    #expect(vm.goals?.stepsDaily == 12000)
    #expect(vm.savedAt != nil)
}

@Test @MainActor func goalsSetupSaveUpsertsGoalTargetsMirror() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    #expect(try store.loadGoalTargetsMirror() == nil)
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), goalStore: store)
    await vm.load()
    _ = await vm.save(GoalsUpdate(stepsDaily: 11000))
    let mirror = try #require(try store.loadGoalTargetsMirror())
    #expect(mirror.stepsDaily == 11000)
}

@Test @MainActor func goalsSetupSaveFailurePreservesPreviousGoalsAndReportsError() async throws {
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(updateFails: .network("down")))
    await vm.load()
    let before = vm.goals
    let ok = await vm.save(GoalsUpdate(stepsDaily: 9999))
    #expect(ok == false)
    #expect(vm.goals == before)
    guard case .error = vm.phase else { Issue.record("expected .error phase"); return }
}

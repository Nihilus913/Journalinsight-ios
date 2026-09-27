import Foundation
import Testing
import JICore
import JIPersistence
import JICompute
import JIDesign
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

@Test func nextWorkingWeightIsReadOnlyAndNeverInvented() {
    let rows = nextWorkingWeights(entries: [])
    #expect(rows.map(\.name) == ["Bench press", "Bent-over row"])
    #expect(rows.allSatisfy { $0.kg == nil })
    #expect(goalsTrainingPlanTitle == "Training plan")
}

// MARK: - B-57 W5 C3: next working weight from the progression rule

@Test func nextWorkingWeightRowsCarryTheRuleInWords() {
    func lift(_ id: Int, _ name: String, _ state: ProgressionState, next: Double) -> LiftProgression {
        LiftProgression(exerciseId: id, name: name, sessionName: "Day 2", currentKg: 50, nextKg: next, state: state, sets: 3)
    }
    let rows = nextWorkingWeightRows(lifts: [lift(1, "Bench press", .due(nextKg: 52.5), next: 52.5), lift(2, "Bent-over row", .notYet, next: 50)],
                                     entries: [], autoSuggest: true)
    #expect(rows[0] == NextWorkingWeightRow(name: "Bench press", nextKg: 52.5, caption: "now 50.0 kg · progression earned", auto: true))
    #expect(rows[1] == NextWorkingWeightRow(name: "Bent-over row", nextKg: 50, caption: "now 50.0 kg · up once all sets hit the target", auto: true))
    let empty = nextWorkingWeightRows(lifts: [], entries: [], autoSuggest: true)
    #expect(empty.map(\.caption) == ["No data", "No data"] && empty.allSatisfy { $0.nextKg == nil && !$0.auto })
    let manual = nextWorkingWeightRows(lifts: [lift(1, "Bench press", .manual(lastLiftedKg: 50), next: 50)], entries: [], autoSuggest: false)
    #expect(manual[0].caption == "now 50.0 kg · auto-suggest off, stays at last lifted" && !manual[0].auto)
    #expect(nextWorkingWeightRows(lifts: [lift(1, "Bench press", .noSession, next: 50)], entries: [], autoSuggest: true)[0].caption == "now 50.0 kg · no logged session yet")
}

@Test func nextWorkingWeightRowsFindTheHubsLiftNames() {
    // BUG-11 carried into W5: the service rows carry the hub's names; the plan repeats a lift per session.
    let rows = nextWorkingWeightRows(lifts: [
        LiftProgression(exerciseId: 1, name: "Barbell Bench Press", sessionName: "Day 1", currentKg: 50, nextKg: 50, state: .notYet, sets: 3),
        LiftProgression(exerciseId: 2, name: "Barbell Bench Press", sessionName: "Day 3", currentKg: 50, nextKg: 52.5, state: .due(nextKg: 52.5), sets: 3),
        LiftProgression(exerciseId: 3, name: "Incline Bench Press", sessionName: "Day 3", currentKg: 30, nextKg: 32.5, state: .due(nextKg: 32.5), sets: 3),
        LiftProgression(exerciseId: 4, name: "Barbell Row", sessionName: "Day 1", currentKg: nil, nextKg: nil, state: nil, sets: 3),
    ], entries: [], autoSuggest: true)
    #expect(rows[0] == NextWorkingWeightRow(name: "Bench press", nextKg: 52.5, caption: "now 50.0 kg · progression earned", auto: true))
    // A row with no known weight is "—" + reason, not a number and not "Auto".
    #expect(rows[1].nextKg == nil && rows[1].caption == JIMissingReason.noData.rawValue && !rows[1].auto)
}

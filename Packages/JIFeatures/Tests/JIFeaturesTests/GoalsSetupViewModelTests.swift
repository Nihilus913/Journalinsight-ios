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
    func energy(windowDays: Int) async throws -> EnergyReport { try await inner.energy(windowDays: windowDays) }
    func goals() async throws -> Goals { try await inner.goals() }
}

@Test @MainActor func goalsSetupLoadPopulatesGoals() async throws {
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider())
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.goals?.stepsDaily == 15000)
}

/// W-FIX10 F10-1: GoalsSetup over a `TargetsMirror` whose hub is `hub` (nil = no drainer).
@MainActor func goalsSetupFixture(hub: TargetsHubFake? = TargetsHubFake(), goalStore: GoalStore? = nil,
                                   hubPoll: Bool = false) throws -> (GoalsSetupViewModel, TargetsMirror, Outbox) {
    let db = try AppDatabase.inMemory()
    let outbox = Outbox(db: db)
    var drainer: OutboxDrainer?
    if let hub { drainer = OutboxDrainer(outbox: outbox, hub: hub) }
    let targets = TargetsMirror(prefs: PrefStore(db: db), outbox: outbox, drainer: drainer)
    var pending: (@MainActor () -> Bool)?
    if hubPoll { pending = { GoalsSetupViewModel.goalsPending(in: outbox) } }
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), goalStore: goalStore, mirror: GoalsMirror(targets: targets),
                                 hubPendingSource: pending, hubPollInterval: .milliseconds(10))
    return (vm, targets, outbox)
}

/// W-FIX10 F10-1 (audit 03-F1): weight / strength / steps go into the phone's targets document and
/// reach the hub as the ONE targets body — never `PUT /planning/goals` (removed hub-side, a 405).
@Test @MainActor func goalsSetupSaveWritesTheTargetsDocumentAndMirrorsIt() async throws {
    let hub = TargetsHubFake()
    let (vm, targets, outbox) = try goalsSetupFixture(hub: hub)
    await vm.load()
    let ok = await vm.save(GoalsUpdate(weight: .init(targetKg: 74, targetDate: "2026-12-31"),
                                       strength: [.init(exercise: "bench", targetKg: 102.5), .init(exercise: "row", targetKg: 100)],
                                       stepsDaily: 12000))
    #expect(ok)
    #expect(vm.phase == .loaded)
    #expect(vm.savedAt != nil)
    #expect(!vm.hubPending)
    let doc = targets.store.load()
    #expect(doc.goals.weight?.targetKg == 74 && doc.goals.weight?.targetDate == "2026-12-31")
    #expect(doc.goals.stepsDaily == 12000)
    #expect(doc.goals.strength == [StrengthGoal(exercise: "bench", targetKg: 102.5), StrengthGoal(exercise: "row", targetKg: 100)])
    #expect(hub.puts.last?.goals.stepsDaily == 12000)
    #expect(try outbox.pending().isEmpty)
    #expect(try outbox.pending().allSatisfy { $0.kind != OutboxDrainer.legacyGoalsKind })
    // The screen shows the edited document at once.
    #expect(vm.goals?.stepsDaily == 12000 && vm.goals?.weight.targetKg == 74)
}

@Test @MainActor func goalsSetupSaveKeepsNutritionAndTheBaseWeight() async throws {
    let (vm, targets, _) = try goalsSetupFixture()
    await targets.update { d in
        d.goals.proteinG = 160
        d.goals.weight = WeightTarget(baseKg: 82, targetKg: 76, targetDate: "2026-11-30")
    }
    await vm.load()
    _ = await vm.save(GoalsUpdate(weight: .init(targetKg: 75, targetDate: nil), stepsDaily: nil))
    let g = targets.store.load().goals
    #expect(g.proteinG == 160)                 // nutrition saves through saveNutrition, untouched here
    #expect(g.weight?.baseKg == 82)
    #expect(g.weight?.targetKg == 75)
    #expect(g.weight?.targetDate == nil)       // the date switched off
    #expect(g.stepsDaily == nil)               // no step goal
}

@Test @MainActor func goalsSetupSaveUpsertsGoalTargetsMirror() async throws {
    let store = GoalStore(db: try AppDatabase.inMemory())
    #expect(try store.loadGoalTargetsMirror() == nil)
    let (vm, _, _) = try goalsSetupFixture(goalStore: store)
    await vm.load()
    _ = await vm.save(GoalsUpdate(stepsDaily: 11000))
    let mirror = try #require(try store.loadGoalTargetsMirror())
    #expect(mirror.stepsDaily == 11000)
}

/// Offline is not an error: the save lands on this phone, the body stays queued, and "hub sync
/// pending" clears once it is delivered.
@Test @MainActor func goalsSetupOfflineSaveIsLocalAndQueued() async throws {
    let hub = TargetsHubFake(); hub.fail = .network("down")
    let (vm, targets, outbox) = try goalsSetupFixture(hub: hub, hubPoll: true)
    await vm.load()
    let ok = await vm.save(GoalsUpdate(stepsDaily: 9999))
    #expect(ok)
    #expect(vm.phase == .loaded)
    #expect(vm.hubPending)
    #expect(targets.store.load().goals.stepsDaily == 9999)
    #expect(try outbox.pending().map(\.kind) == [TargetsDocument.outboxKind])
    hub.fail = nil
    #expect(await targets.pushIfPending())
    for _ in 0..<100 where vm.hubPending { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!vm.hubPending)
    #expect(hub.puts.last?.goals.stepsDaily == 9999)
}

@Test @MainActor func goalsSetupWithoutATargetsStoreSaysSoAndKeepsTheGoals() async throws {
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider())
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

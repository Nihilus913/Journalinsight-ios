import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// `TrainingProviding` double — mirrors `RecoveryFlakyProvider`'s "can be told to fail" shape,
/// scoped to this lane's own protocol.
nonisolated final class TrainingFakeProvider: TrainingProviding, @unchecked Sendable {
    var failing = false
    var error: HubError = .network("simulated")
    var day = TrainingDayDetail(date: "2026-09-11", activities: [], exerciseSets: [])
    var exerciseRows: [Exercise] = [
        Exercise(exerciseId: 19, sessionName: "Day 1 Full Upper", exerciseName: "Barbell Bench Press", sets: 3, repsTarget: "6-12", currentWeightKg: 50, progressionStepKg: 2.5),
    ]
    var updateResult: (Int, ExerciseUpdate) throws -> ExerciseUpdateResult = { id, _ in ExerciseUpdateResult(exerciseId: id, updated: true) }

    func trainingDay(date: String) async throws -> TrainingDayDetail { if failing { throw error }; return day }
    func exercises() async throws -> [Exercise] { if failing { throw error }; return exerciseRows }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult { try updateResult(exerciseId, patch) }
}

@MainActor
private func makeVM(
    training: TrainingFakeProvider = TrainingFakeProvider(),
    health: any HealthDataProvider = MockDataProvider(),
    cache: OfflineCache? = nil,
    now: @escaping () -> Date = { ISO8601DateFormatter().date(from: "2026-09-11T08:00:00Z")! }
) throws -> TrainingViewModel {
    TrainingViewModel(
        provider: training, healthProvider: health,
        cache: cache ?? OfflineCache(db: try! AppDatabase.inMemory()),
        strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "w3a.l3.vm.\(UUID().uuidString)")),
        now: now
    )
}

@Test @MainActor func trainingLoadPopulatesGateMorningAndExercises() async throws {
    let vm = try makeVM()
    await vm.load()
    try await Task.sleep(for: .milliseconds(50)) // dayDetail loads independently, fire-and-forget (see loadDay)
    #expect(vm.phase == .loaded)
    #expect(vm.gate != nil)
    #expect(vm.morning != nil)
    #expect(vm.exercises.isEmpty == false)
    #expect(vm.dayDetail != nil)
}

@Test @MainActor func trainingSelectDateReloadsDayDetailOnly() async throws {
    let training = TrainingFakeProvider()
    let vm = try makeVM(training: training)
    await vm.load()
    let gateBefore = vm.gate

    training.day = TrainingDayDetail(date: "2026-09-05", activities: [], exerciseSets: [])
    vm.selectDate("2026-09-05")
    try await Task.sleep(for: .milliseconds(50))

    #expect(vm.selectedDate == "2026-09-05")
    #expect(vm.dayDetail?.date == "2026-09-05")
    #expect(vm.gate == gateBefore) // untouched by the day-strip tap-through
}

@Test @MainActor func trainingUpdateExerciseAppliesOptimisticallyOnSuccess() async throws {
    let training = TrainingFakeProvider()
    let vm = try makeVM(training: training)
    await vm.load()
    let ex = try #require(vm.exercises.first)

    await vm.updateExercise(exerciseId: ex.exerciseId, exerciseName: ex.exerciseName, patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5, sets: 3, repsTarget: 10))

    #expect(vm.exercises.first?.currentWeightKg == 52.5)
    #expect(vm.updateFailed.isEmpty)
    #expect(vm.pendingUpdates.isEmpty)
}

@Test @MainActor func trainingUpdateExerciseRevertsOnNamedHubErrorAndFlagsFailure() async throws {
    let training = TrainingFakeProvider()
    training.updateResult = { _, _ in throw HubError.unauthorized }
    let vm = try makeVM(training: training)
    await vm.load()
    let ex = try #require(vm.exercises.first)
    let originalWeight = ex.currentWeightKg

    await vm.updateExercise(exerciseId: ex.exerciseId, exerciseName: ex.exerciseName, patch: ExerciseUpdate(currentWeightKg: 999, progressionStepKg: 2.5))

    #expect(vm.exercises.first?.currentWeightKg == originalWeight) // reverted, never left at a value that never stuck
    #expect(vm.updateFailed.contains(ex.exerciseId))
}

@Test @MainActor func trainingUpdateExerciseFallsBackLocallyOnNetworkErrorWithoutReverting() async throws {
    let training = TrainingFakeProvider()
    training.updateResult = { _, _ in throw HubError.network("hub unreachable") }
    let strengthStore = StrengthStateStore(defaults: UserDefaults(suiteName: "w3a.l3.vm.\(UUID().uuidString)"))
    let vm = TrainingViewModel(provider: training, healthProvider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()), strengthStore: strengthStore)
    await vm.load()
    let ex = try #require(vm.exercises.first)

    await vm.updateExercise(exerciseId: ex.exerciseId, exerciseName: ex.exerciseName, patch: ExerciseUpdate(currentWeightKg: 55.0, progressionStepKg: 2.5))

    #expect(vm.exercises.first?.currentWeightKg == 55.0) // local-first: the tap is not lost
    #expect(vm.updateFailed.isEmpty)
    #expect(strengthStore.getLocal(exerciseId: ex.exerciseId)?.currentWeightKg == 55.0)
}

@Test @MainActor func trainingHubDownFallsBackToCacheAndFlagsStale() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    await (try makeVM(training: TrainingFakeProvider(), cache: cache)).load() // warm the cache
    let failing = TrainingFakeProvider(); failing.failing = true
    let vm = try makeVM(training: failing, cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable == false)
    #expect(vm.gate != nil)
}

@Test @MainActor func trainingScreenStateFlagsYazioAuthExpired() async throws {
    let failing = TrainingFakeProvider()
    failing.failing = true
    failing.error = .yazioAuthExpired(detail: "token stale")
    let vm = try makeVM(training: failing)
    await vm.load()
    #expect(vm.screenState == .yazioAuthExpired(detail: "token stale"))
}

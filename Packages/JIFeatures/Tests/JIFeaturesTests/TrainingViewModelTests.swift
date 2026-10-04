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
    /// B-45 (c): nil = behave like a hub without the route (the protocol's default throws).
    var planSessionUpdate: ((Int, Int?) throws -> PlanSessionOut)?

    func trainingDay(date: String) async throws -> TrainingDayDetail { if failing { throw error }; return day }
    func exercises() async throws -> [Exercise] { if failing { throw error }; return exerciseRows }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult { try updateResult(exerciseId, patch) }
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut {
        guard let planSessionUpdate else { throw PlanSessionUpdateUnavailable() }
        return try planSessionUpdate(sessionId, weekday)
    }
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

// MARK: - W-B54 (B54-1): lift edits are outbox-first

nonisolated final class LiftOutboxFakeProvider: TrainingProviding, ExercisePatchProviding, @unchecked Sendable {
    var rows: [Exercise] = [
        Exercise(exerciseId: 19, sessionName: "Day 1 Full Upper", exerciseName: "Barbell Bench Press", sets: 3, repsTarget: "6-12", currentWeightKg: 50, progressionStepKg: 2.5),
    ]
    var updateError: Error?
    var updates: [(Int, ExerciseUpdate)] = []
    func trainingDay(date: String) async throws -> TrainingDayDetail { TrainingDayDetail(date: date, activities: [], exerciseSets: []) }
    func exercises() async throws -> [Exercise] { rows }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        updates.append((exerciseId, patch))
        if let updateError { throw updateError }
        return ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }
}

@MainActor
private func makeLiftVM(_ hub: LiftOutboxFakeProvider, outbox: Outbox, store: StrengthStateStore) -> TrainingViewModel {
    TrainingViewModel(
        provider: hub, healthProvider: MockDataProvider(), cache: OfflineCache(db: try! AppDatabase.inMemory()),
        strengthStore: store, outbox: outbox,
        drainer: OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: hub, strengthStore: store),
        now: { ISO8601DateFormatter().date(from: "2026-10-04T08:00:00Z")! }
    )
}

@Test @MainActor func anOfflineLiftEditStandsIsQueuedAndMarkedPending() async throws {
    let hub = LiftOutboxFakeProvider()
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let store = StrengthStateStore(defaults: UserDefaults(suiteName: "b54.vm.\(UUID().uuidString)"))
    let vm = makeLiftVM(hub, outbox: outbox, store: store)
    await vm.load()
    hub.updateError = HubError.network("hub unreachable")

    await vm.updateExercise(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5, sets: 3))

    #expect(vm.exercises.first { $0.exerciseId == 19 }?.currentWeightKg == 52.5)
    #expect(vm.updateFailed.isEmpty)
    #expect(vm.pendingUpdates.isEmpty)
    #expect(vm.pendingExerciseSync == [19])
    let rows = try outbox.pending()
    #expect(rows.count == 1)
    #expect(rows.first?.kind == "exercise_patch")
    #expect(store.getLocal(exerciseId: 19)?.currentWeightKg == 52.5)

    // The hub comes back: any drain (watchdog, retry scheduler, the next tap) clears the marker.
    hub.updateError = nil
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: hub, strengthStore: store).drainOnce()
    vm.reconcilePendingSync()
    #expect(vm.pendingExerciseSync.isEmpty)
    #expect(try outbox.pending().isEmpty)
    #expect(hub.updates.last?.1.currentWeightKg == 52.5)
    #expect(store.getLocal(exerciseId: 19)?.synced == true)
}

@Test @MainActor func anOnlineLiftEditIsSentInTapAndLeavesNothingQueued() async throws {
    let hub = LiftOutboxFakeProvider()
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let store = StrengthStateStore(defaults: UserDefaults(suiteName: "b54.vm.\(UUID().uuidString)"))
    let vm = makeLiftVM(hub, outbox: outbox, store: store)
    await vm.load()

    await vm.updateExercise(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5))

    #expect(hub.updates.count == 1)
    #expect(vm.exercises.first?.currentWeightKg == 52.5)
    #expect(vm.pendingExerciseSync.isEmpty)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func aRefusedLiftEditRollsBackAndSaysSo() async throws {
    let hub = LiftOutboxFakeProvider()
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let store = StrengthStateStore(defaults: UserDefaults(suiteName: "b54.vm.\(UUID().uuidString)"))
    let vm = makeLiftVM(hub, outbox: outbox, store: store)
    await vm.load()
    hub.updateError = HubError.http(status: 422, detail: "bad weight")

    await vm.updateExercise(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: -5, progressionStepKg: 2.5))

    #expect(vm.exercises.first?.currentWeightKg == 50)
    #expect(vm.updateFailed == [19])
    #expect(vm.pendingExerciseSync.isEmpty)
    #expect(try outbox.pending().isEmpty)
    #expect(store.getLocal(exerciseId: 19)?.currentWeightKg != -5)
}

@Test @MainActor func aRefreshWhileALiftEditIsQueuedKeepsTheQueuedValue() async throws {
    let hub = LiftOutboxFakeProvider()
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let store = StrengthStateStore(defaults: UserDefaults(suiteName: "b54.vm.\(UUID().uuidString)"))
    let vm = makeLiftVM(hub, outbox: outbox, store: store)
    await vm.load()
    hub.updateError = HubError.network("offline")
    await vm.updateExercise(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5))

    await vm.refresh()   // reads answer (old 50 kg), the write is still queued

    #expect(vm.exercises.first { $0.exerciseId == 19 }?.currentWeightKg == 52.5)
}

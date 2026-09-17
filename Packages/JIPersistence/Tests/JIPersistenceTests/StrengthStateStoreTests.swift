import Foundation
import Testing
import JICore
@testable import JIPersistence

private func freshSuite() -> UserDefaults {
    let name = "w3a.l3.tests.strengthState.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    suite.removePersistentDomain(forName: name)
    return suite
}

@Test func strengthStateSavesAndReadsBack() throws {
    let store = StrengthStateStore(defaults: freshSuite())
    store.saveLocal(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5, sets: 3, repsTarget: 10))
    let row = try #require(store.getLocal(exerciseId: 19))
    #expect(row.exerciseName == "Barbell Bench Press")
    #expect(row.currentWeightKg == 52.5)
    #expect(row.progressionStepKg == 2.5)
    #expect(row.sets == 3)
    #expect(row.repsTarget == 10)
    #expect(row.synced == false)
}

/// The exit criterion this file exists to prove: a lift stepper's write survives an app relaunch
/// — modeled here as constructing a brand-new `StrengthStateStore` instance over the SAME
/// `UserDefaults` suite (an app-group suite is exactly this: durable storage independent of any
/// in-memory object's lifetime).
@Test func strengthStatePersistsAcrossStoreRelaunch() throws {
    let suite = freshSuite()
    StrengthStateStore(defaults: suite).saveLocal(exerciseId: 20, exerciseName: "Barbell Row", patch: ExerciseUpdate(currentWeightKg: 55.0, progressionStepKg: 2.5))

    let relaunched = StrengthStateStore(defaults: suite)
    let row = try #require(relaunched.getLocal(exerciseId: 20))
    #expect(row.currentWeightKg == 55.0)
    #expect(row.exerciseName == "Barbell Row")
}

@Test func strengthStateGetLocalIsNilForUnknownExercise() {
    let store = StrengthStateStore(defaults: freshSuite())
    #expect(store.getLocal(exerciseId: 999) == nil)
}

@Test func markSyncedFlipsSyncedFlagOnly() throws {
    let store = StrengthStateStore(defaults: freshSuite())
    store.saveLocal(exerciseId: 21, exerciseName: "DB Shoulder Press", patch: ExerciseUpdate(currentWeightKg: 12.5, progressionStepKg: 2.5))
    #expect(store.listUnsynced().map(\.exerciseId) == [21])
    store.markSynced(exerciseId: 21)
    #expect(store.listUnsynced().isEmpty)
    let row = try #require(store.getLocal(exerciseId: 21))
    #expect(row.synced)
    #expect(row.currentWeightKg == 12.5)
}

@Test func markSyncedOnUnknownExerciseIsANoOp() {
    let store = StrengthStateStore(defaults: freshSuite())
    store.markSynced(exerciseId: 404) // must not crash
    #expect(store.getLocal(exerciseId: 404) == nil)
}

@Test func updateExerciseLocalFirstMirrorsSuccessfulHubWriteAndMarksSynced() async throws {
    let store = StrengthStateStore(defaults: freshSuite())
    let result = try await updateExerciseLocalFirst(
        store: store, exerciseId: 22, exerciseName: "DB Biceps Curl",
        patch: ExerciseUpdate(currentWeightKg: 14.0, progressionStepKg: 1.25)
    ) { id, patch in ExerciseUpdateResult(exerciseId: id, updated: true) }

    #expect(result.updated)
    let row = try #require(store.getLocal(exerciseId: 22))
    #expect(row.synced)
    #expect(row.currentWeightKg == 14.0)
}

@Test func updateExerciseLocalFirstFallsBackToLocalOnNetworkError() async throws {
    let store = StrengthStateStore(defaults: freshSuite())
    let result = try await updateExerciseLocalFirst(
        store: store, exerciseId: 23, exerciseName: "Diamond Push-Up",
        patch: ExerciseUpdate(currentWeightKg: 0, progressionStepKg: 0)
    ) { _, _ in throw HubError.network("hub unreachable") }

    #expect(result.updated)
    let row = try #require(store.getLocal(exerciseId: 23))
    #expect(row.synced == false)
}

@Test func updateExerciseLocalFirstRethrowsNonNetworkErrors() async {
    let store = StrengthStateStore(defaults: freshSuite())
    await #expect(throws: HubError.self) {
        _ = try await updateExerciseLocalFirst(
            store: store, exerciseId: 24, exerciseName: "Plank",
            patch: ExerciseUpdate(currentWeightKg: 0, progressionStepKg: 0)
        ) { _, _ in throw HubError.unauthorized }
    }
    #expect(store.getLocal(exerciseId: 24) == nil)
}

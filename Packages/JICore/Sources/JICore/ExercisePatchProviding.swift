import Foundation

/// W-B54 (B54-1): the lift edit (`PUT /api/v1/planning/exercises/{id}`) seen through the narrow
/// protocol `OutboxDrainer` replays `"exercise_patch"` rows with — same idiom as
/// `PlanSessionWeekdayProviding`: the drainer asks "can this app instance deliver this kind?"
/// without depending on a screen's whole `TrainingProviding` slice. `HubDataProvider` conforms
/// with the `updateExercise` it already has for `TrainingProviding`.
public protocol ExercisePatchProviding: Sendable {
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult
}

/// The `Outbox` payload for an `"exercise_patch"` row. `exerciseName` is not needed for the PUT —
/// it is carried so the drainer can keep `StrengthStateStore`'s local mirror row named, and a
/// later launch can describe the queued edit. camelCase keys on purpose: the outbox's own storage
/// format (plain `JSONEncoder()`); the nested `patch` keeps `ExerciseUpdate`'s snake_case keys.
public struct ExercisePatchBody: Codable, Sendable, Equatable {
    public var exerciseId: Int
    public var exerciseName: String
    public var patch: ExerciseUpdate
    public init(exerciseId: Int, exerciseName: String, patch: ExerciseUpdate) {
        self.exerciseId = exerciseId; self.exerciseName = exerciseName; self.patch = patch
    }
}

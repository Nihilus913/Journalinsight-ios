import Foundation

/// Previews + tests only, same contract as `MockDataProvider`'s own methods (frozen file — this
/// conformance lives here instead, per the Data seam). Serves the synced hub-contract fixtures via
/// the type's public `fixtureURL(named:)` lookup rather than its `private load(_:as:)` helper,
/// which is out of reach from a different file under Swift's file-scoped `private`.
extension MockDataProvider: TrainingProviding {
    public func trainingDay(date: String) async throws -> TrainingDayDetail {
        try Self.loadTrainingFixture("training_day", as: TrainingDayDetail.self)
    }

    public func exercises() async throws -> [Exercise] {
        try Self.loadTrainingFixture("planning_exercises", as: [Exercise].self)
    }

    /// No mock hub to PATCH against — resolves immediately as a successful, no-op write, same as a
    /// real hub's `{exercise_id, updated: true}` reply shape.
    public func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }

    private static func loadTrainingFixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        guard let url = MockDataProvider.fixtureURL(named: name) else {
            throw HubError.decoding("missing fixture \(name)")
        }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }
}

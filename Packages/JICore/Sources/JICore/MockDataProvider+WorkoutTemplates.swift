import Foundation

/// B-37-L1 — `MockDataProvider`'s `WorkoutTemplatesProviding` conformance: the 4 seed rows of
/// `plan.workout_template` (migration 046), served from the library's own hub-contract fixture copy
/// (`Fixtures/hub-contract/planning_workout_templates.json`), same `fixtureURL(named:)` pattern as
/// `MockDataProvider+Goals.swift`.
extension MockDataProvider: WorkoutTemplatesProviding {
    public func workoutTemplates() async throws -> [WorkoutTemplate] {
        guard let url = Self.fixtureURL(named: "planning_workout_templates")
        else { throw HubError.decoding("missing fixture planning_workout_templates") }
        return try JSON.decoder.decode([WorkoutTemplate].self, from: Data(contentsOf: url))
    }
}

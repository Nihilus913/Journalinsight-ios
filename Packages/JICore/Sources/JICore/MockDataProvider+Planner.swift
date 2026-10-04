import Foundation

/// W-PLANNER PL-3 — previews and fixture screens: the mock has no `/planning/workouts` fixture of
/// record, so it serves exactly what an old hub's phone shows — the fallback over its own synced
/// exercise + template fixtures.
extension MockDataProvider: PlannerProviding {
    public func plannerWorkouts() async throws -> [PlannerWorkout] {
        plannerWorkoutsFallback(exercises: try await exercises(), planSessions: [], templates: try await workoutTemplates())
    }
}

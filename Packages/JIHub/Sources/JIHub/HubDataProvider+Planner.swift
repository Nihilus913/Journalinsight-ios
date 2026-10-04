import JICore

/// W-PLANNER PL-3 — `HubDataProvider`'s `PlannerProviding` conformance. The route returns a bare
/// JSON array. An older hub answers 404: that is `PlannerWorkoutsUnavailable`, so the Planner
/// builds the list from its cached rows instead of showing an error.
extension HubDataProvider: PlannerProviding {
    public func plannerWorkouts() async throws -> [PlannerWorkout] {
        do {
            return try await client.get("/api/v1/planning/workouts")
        } catch HubError.http(status: 404, _) {
            throw PlannerWorkoutsUnavailable()
        }
    }
}

import JICore

/// B-37-L1 — `HubDataProvider`'s `WorkoutTemplatesProviding` conformance (Wave Card B-37 ## Contract).
/// The route returns a bare JSON array (no envelope), decoded straight into `[WorkoutTemplate]`.
extension HubDataProvider: WorkoutTemplatesProviding {
    public func workoutTemplates() async throws -> [WorkoutTemplate] {
        try await client.get("/api/v1/planning/workout-templates")
    }
}

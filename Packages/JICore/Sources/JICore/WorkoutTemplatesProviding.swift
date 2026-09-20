import Foundation

/// B-37-L1 (P-training) — the "Send to Watch" sheet's own read slice (one protocol per screen's
/// hub routes, same rationale as `GoalsProviding`/`KpiTargetsProviding`). Consumed by
/// `JIWorkouts.WorkoutBuilder` (via the sheet VM); `HubDataProvider` and `MockDataProvider` conform.
public protocol WorkoutTemplatesProviding: Sendable {
    /// `GET /api/v1/planning/workout-templates`
    func workoutTemplates() async throws -> [WorkoutTemplate]
}

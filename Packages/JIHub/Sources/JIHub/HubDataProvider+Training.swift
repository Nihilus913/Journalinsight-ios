import Foundation
import JICore

/// `HubDataProvider.client` was widened to internal by L0 (W3b, B-14) — this conformance now
/// uses the shared `client` directly instead of re-deriving its own `HubClient` from the
/// persisted `ConnectionConfig` (the W3a workaround). `updateExercise` uses `client.send("PUT", …)`
/// — the hub router (`app/planning/router.py`) exposes `PUT /api/v1/planning/exercises/{id}`, not
/// PATCH.
extension HubDataProvider: TrainingProviding {
    public func trainingDay(date: String) async throws -> TrainingDayDetail {
        try await client.get("/api/v1/training/day/\(date)")
    }

    public func exercises() async throws -> [Exercise] {
        try await client.get("/api/v1/planning/exercises")
    }

    public func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        try await client.send("PUT", "/api/v1/planning/exercises/\(exerciseId)", body: patch)
    }

    /// W-B46 Contract (L3's new route). Same `send("PUT", …)` seam as `updateExercise`.
    public func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut {
        try await client.send("PUT", "/api/v1/planning/plan-sessions/\(sessionId)", body: PlanSessionWeekdayUpdate(weekday: weekday))
    }
}

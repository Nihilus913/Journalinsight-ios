import Foundation

/// W-PLANNER PL-3 — previews and fixture screens: the mock has no `/planning/workouts` fixture of
/// record, so it builds the list over its own synced exercise + template fixtures.
/// W-B88: in the post-073 shape — each strength day is its library template (t5…t8), linked to
/// its plan session by id, so previews and fixture screens exercise the one-model rows. The synced
/// exercise fixture names its sessions only; the mock numbers them in plan order (1…4), as the
/// live plan does (`plan.plan_session` 1–4 = Day 1–4).
extension MockDataProvider: PlannerProviding {
    public func plannerWorkouts() async throws -> [PlannerWorkout] {
        var n = 0
        let rows = plannerWorkoutsFallback(exercises: try await exercises(), planSessions: [], templates: try await workoutTemplates())
            .map { row -> PlannerWorkout in
                guard row.kind == .planSession, row.sessionId == nil else { return row }
                n += 1
                var r = row; r.ref = "s\(n)"; return r
            }
        return plannerStrengthDaysAsTemplates(rows)
    }
}

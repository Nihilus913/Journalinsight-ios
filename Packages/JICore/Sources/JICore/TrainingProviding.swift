/// The Training tab's own hub slice (W3a-L3), added alongside the frozen `HealthDataProvider`
/// rather than into it (Data seam: three screen lanes land in parallel this wave — a shared
/// protocol file would collide). `HubDataProvider`/`MockDataProvider` conform via their own
/// `+Training` extension files; `TrainingView`'s gate/verdict summary keeps reading the existing,
/// frozen `HealthDataProvider.gate(windowDays:)` / `.morning()` instead of duplicating them here.
public protocol TrainingProviding: Sendable {
    /// `GET /api/v1/training/day/{date}`
    func trainingDay(date: String) async throws -> TrainingDayDetail

    /// `GET /api/v1/planning/exercises`
    func exercises() async throws -> [Exercise]

    /// `PATCH /api/v1/planning/exercises/{exercise_id}`
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult

    /// `PUT /api/v1/planning/plan-sessions/{id}` (W-B46 Contract, B-45 (c)) — assigns a plan
    /// session to a weekday (Mon = 0 … Sun = 6) or clears it with `nil`. Defaulted, so a provider
    /// written before the route existed (fixtures, `MockDataProvider`) still conforms and simply
    /// reports the feature as unavailable instead of pretending the write landed.
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut

    /// `GET /api/v1/planning/plan-sessions` (W-B40 fixer, B40-V1) — every session of the active
    /// plan, cardio and rest included (the exercise rows only carry sessions that have lifts).
    /// Defaulted: a provider without the route reports it unavailable and the app falls back to
    /// the morning-call schedule for the cardio days.
    func planSessions() async throws -> [PlanSessionOut]

    /// `GET /api/v1/planning/week?start=` (W-SSOT-1 SS-7) — the hub's seven-day schedule, one
    /// `session_for` answer per date. Defaulted: an older hub (no route) throws
    /// `PlanWeekUnavailable` and the resolver falls back to `planSessions()`.
    func planWeek(start: String) async throws -> PlanWeekOut
}

public extension TrainingProviding {
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut {
        throw PlanSessionUpdateUnavailable()
    }

    func planSessions() async throws -> [PlanSessionOut] {
        throw PlanSessionListUnavailable()
    }

    func planWeek(start: String) async throws -> PlanWeekOut {
        throw PlanWeekUnavailable()
    }
}

public struct PlanSessionListUnavailable: Error, Sendable, Equatable {
    public init() {}
}

public struct PlanSessionUpdateUnavailable: Error, Sendable, Equatable {
    public init() {}
}

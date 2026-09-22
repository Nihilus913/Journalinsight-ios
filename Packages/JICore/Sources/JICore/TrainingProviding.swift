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
}

public extension TrainingProviding {
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut {
        throw PlanSessionUpdateUnavailable()
    }
}

public struct PlanSessionUpdateUnavailable: Error, Sendable, Equatable {
    public init() {}
}

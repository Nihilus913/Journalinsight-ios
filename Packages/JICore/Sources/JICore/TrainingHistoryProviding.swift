import Foundation

/// W-OFFLINE2 OFF2-4 (B-50 slice 2): the completed-workouts history a data source can answer
/// WITHOUT the hub — the on-device HealthKit adapter (`HKTrainingHistoryReader`) conforms. Rows
/// are `DayActivity`s (newest first) so the Training tab draws them with the hub's own
/// `CompletedWorkoutRow`; `startTimeUtc` carries each row's day.
public protocol TrainingHistoryProviding: Sendable {
    /// Workouts that started in the last `days` local calendar days (today included), newest first.
    func recentWorkouts(days: Int) async throws -> [DayActivity]
}

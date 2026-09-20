#if canImport(WorkoutKit)
import Foundation
import WorkoutKit

/// B-37-L1 (P-workouts) — the seam over `WorkoutScheduler.shared` (spec §3) so the Training
/// "Send to Watch" sheet and its tests run without a Watch. L2's `WorkoutSchedulerSender` is the
/// real conformance; `FakeWorkoutSender` records calls.
public protocol WorkoutSending: Sendable {
    /// `true` when the user granted WorkoutKit scheduling authorization.
    func requestAuthorization() async throws -> Bool
    func schedule(_ plan: WorkoutPlan, at date: DateComponents) async throws
    func remove(_ plan: WorkoutPlan, at date: DateComponents) async throws
    func scheduledWorkouts() async throws -> [ScheduledWorkoutPlan]
}
#endif

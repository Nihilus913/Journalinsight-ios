import Foundation
import HealthKit
import Testing
import WorkoutKit
@testable import JIWorkouts

/// B-37-L2 spike (spec §4) — the answers are read off the sim test log and reported in the lane's
/// `spike:`. These tests RECORD, they do not gate: a `false` here is a finding, not a failure.
struct WorkoutKitSpikeTests {
    @Test func supportsHeartRateRangeAlertForRunningByLocation() {
        let alert = HeartRateRangeAlert.heartRate(100...140)
        let outdoor = CustomWorkout.supportsAlert(alert, activity: .running, location: .outdoor)
        let indoor = CustomWorkout.supportsAlert(alert, activity: .running, location: .indoor)
        let unknown = CustomWorkout.supportsAlert(alert, activity: .running)
        print("SPIKE supportsAlert(HeartRateRangeAlert, .running): outdoor=\(outdoor) indoor=\(indoor) unknown=\(unknown)")
        print("SPIKE supportsGoal(.time, .running): outdoor=\(CustomWorkout.supportsGoal(.time(60, .seconds), activity: .running, location: .outdoor)) indoor=\(CustomWorkout.supportsGoal(.time(60, .seconds), activity: .running, location: .indoor))")
        print("SPIKE supportsActivity(.running)=\(CustomWorkout.supportsActivity(.running)) WorkoutScheduler.isSupported=\(WorkoutScheduler.isSupported) maxAllowedScheduledWorkoutCount=\(WorkoutScheduler.maxAllowedScheduledWorkoutCount)")
        #expect(outdoor || indoor || !outdoor, "recording only")
    }

    @Test func workoutStepDisplayNameIsAvailable() {
        // `WorkoutStep.displayName` is `@available(iOS 18.0, watchOS 11.0, *)` in the iOS 27.0 SDK
        // swiftinterface; JIWorkouts deploys at iOS 27 / watchOS 27 so no guard is needed.
        let step = WorkoutStep(goal: .time(60, .seconds), alert: .heartRate(100...140), displayName: "Warm-up")
        print("SPIKE WorkoutStep.displayName compiles on iOS 27 SDK, value=\(step.displayName ?? "nil")")
        #expect(step.displayName == "Warm-up")
    }
}

import Foundation
import Testing
import WorkoutKit
@testable import JIWorkouts

/// B-37-L2 — what is testable without a Watch: the `isSupported` guard (every call throws
/// `.unsupported` and never reaches `WorkoutScheduler.shared`) and the auth-state mapping.
/// The happy path (real scheduling) is device evidence (parity-milestone rule).
struct WorkoutSchedulerSenderTests {
    private let plan = WorkoutPlan(.custom(CustomWorkout(activity: .running, location: .outdoor, displayName: "T")))
    private let date = DateComponents(year: 2026, month: 9, day: 22)

    @Test func unsupportedGuardThrowsOnEveryCall() async {
        let sender = WorkoutSchedulerSender(isSupported: { false })
        await #expect(throws: WorkoutSchedulerSenderError.unsupported) { _ = try await sender.requestAuthorization() }
        await #expect(throws: WorkoutSchedulerSenderError.unsupported) { try await sender.schedule(plan, at: date) }
        await #expect(throws: WorkoutSchedulerSenderError.unsupported) { try await sender.remove(plan, at: date) }
        await #expect(throws: WorkoutSchedulerSenderError.unsupported) { _ = try await sender.scheduledWorkouts() }
    }

    @Test func onlyAuthorizedCountsAsGranted() {
        #expect(WorkoutSchedulerSender.granted(.authorized))
        #expect(!WorkoutSchedulerSender.granted(.denied))
        #expect(!WorkoutSchedulerSender.granted(.restricted))
        #expect(!WorkoutSchedulerSender.granted(.notDetermined))
    }

    @Test func unsupportedErrorHasUserCopy() {
        #expect(WorkoutSchedulerSenderError.unsupported.errorDescription?.contains("Apple Watch") == true)
    }
}

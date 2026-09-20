import Foundation
import Testing
import WorkoutKit
@testable import JIWorkouts

/// B-37-L1 — the fake records a schedule call with the plan id and the picked date.
@Test func fakeSenderRecordsSchedule() async throws {
    let sender = FakeWorkoutSender()
    let plan = WorkoutPlan(.custom(CustomWorkout(activity: .running, location: .outdoor, displayName: "Smoke")))
    let date = DateComponents(year: 2026, month: 9, day: 21)

    #expect(try await sender.requestAuthorization())
    try await sender.schedule(plan, at: date)

    let calls = await sender.calls
    #expect(calls == [.requestAuthorization, .schedule(planId: plan.id, at: date)])
    let scheduled = try await sender.scheduledWorkouts()
    #expect(scheduled.count == 1)
    #expect(scheduled[0].date.day == 21 && scheduled[0].date.month == 9 && scheduled[0].date.year == 2026)
}

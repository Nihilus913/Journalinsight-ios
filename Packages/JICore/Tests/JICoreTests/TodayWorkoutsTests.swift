import Foundation
import Testing
@testable import JICore

@Suite struct TodayWorkoutsTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    func w(_ kind: TodayWorkout.Kind, _ name: String, min: Double, source: String? = "Bevel", offset: Double = 0) -> TodayWorkout {
        TodayWorkout(kind: kind, activityName: name, start: t0.addingTimeInterval(offset), end: t0.addingTimeInterval(offset + min * 60), sourceName: source)
    }

    @Test func classifiesPlannedSessions() {
        #expect(PlannedSessionKind.classify("Day 1 Full Upper + Z2 40min") == .strength)
        #expect(PlannedSessionKind.classify("Strength") == .strength)
        #expect(PlannedSessionKind.classify("Long Z2") == .cardio)
        #expect(PlannedSessionKind.classify("Intervals 4x4") == .interval)   // W-FIX9 (audit F3)
        #expect(PlannedSessionKind.classify("Rest") == .rest)
        #expect(PlannedSessionKind.classify(nil) == .unknown)
        #expect(PlannedSessionKind.classify("   ") == .unknown)
    }

    @Test func strengthWorkoutMarksStrengthSessionDone() {
        let lift = w(.strength, "Traditional strength", min: 52)
        let r = SessionCompletion.resolve(planned: .strength, workouts: [w(.cardio, "Walk", min: 20, offset: -3600), lift])
        #expect(r == .done(lift))
        #expect(r.isDone)
        #expect(r.statusText == "Done · Traditional strength · 52 min · Bevel")
    }

    @Test func cardioWorkoutMarksCardioSessionDone() {
        let run = w(.cardio, "Run", min: 45, source: "Workout")
        #expect(SessionCompletion.resolve(planned: .cardio, workouts: [run]) == .done(run))
    }

    @Test func nonMatchingWorkoutIsOtherActivityAndSessionStaysOpen() {
        let walk = w(.cardio, "Walk", min: 30)
        let r = SessionCompletion.resolve(planned: .strength, workouts: [walk])
        #expect(r == .otherActivity(walk))
        #expect(!r.isDone)
        #expect(r.statusText == "Other activity · Walk · 30 min · Bevel")
    }

    @Test func restDayWorkoutIsOtherActivity() {
        let lift = w(.strength, "Functional strength", min: 30)
        #expect(SessionCompletion.resolve(planned: .rest, workouts: [lift]) == .otherActivity(lift))
    }

    @Test func noWorkoutLeavesEverythingUnchanged() {
        #expect(SessionCompletion.resolve(planned: .strength, workouts: []) == .none)
        #expect(SessionCompletion.none.statusText == nil)
    }

    @Test func summaryOmitsMissingSource() {
        #expect(w(.other, "Yoga", min: 20, source: nil).summary == "Yoga · 20 min")
    }
}

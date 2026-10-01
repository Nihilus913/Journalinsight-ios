import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-FIX7 F7-1 (S1): a workout in Apple Health today that matches the planned session marks it
/// done on Decide / Today / Training / the glances; a non-matching one is "other activity".
private struct StubWorkouts: TodayWorkoutsProviding {
    let rows: [TodayWorkout]
    func todayWorkouts() async throws -> [TodayWorkout] { rows }
}

private let t0 = ISO8601DateFormatter().date(from: "2026-09-28T15:00:00Z")!
private let lift = TodayWorkout(kind: .strength, activityName: "Traditional strength", start: t0,
                                end: t0.addingTimeInterval(52 * 60), sourceName: "Bevel")
private let walk = TodayWorkout(kind: .cardio, activityName: "Walk", start: t0, end: t0.addingTimeInterval(30 * 60), sourceName: "Workout")

/// Mon 2026-09-28: strength on Monday (weekday 0) and Wednesday.
private func week(today: String = "2026-09-28", mondayDone: Bool? = nil) -> TrainingWeekSummary {
    let dates = ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"]
    let days = (0..<7).map { wd in
        TrainingWeekDay(weekday: wd, date: dates[wd], kind: wd == 0 || wd == 2 ? .strength : (wd == 5 ? .longRun : .rest),
                        sessionName: wd == 0 ? "Day 1 Full Upper" : (wd == 2 ? "Day 2 Full Upper" : nil), sessionId: wd == 0 ? 1 : (wd == 2 ? 2 : nil),
                        done: wd == 0 ? mondayDone : nil, isToday: dates[wd] == today)
    }
    return TrainingWeekSummary(days: days, planTotal: 2, assigned: 2, planDone: 0, next: days[0])
}

@MainActor @Test func workoutsModelReadsTodayAndStaysEmptyWithoutASource() async {
    let empty = TodayWorkoutsModel(source: nil)
    await empty.refresh()
    #expect(empty.workouts.isEmpty)

    var changes = 0
    // W-FIX10 F10-6: the clock is injected — "today" is t0's day, not the run date (the
    // default `Date.init` made this fail from 2026-09-29 on).
    let model = TodayWorkoutsModel(source: StubWorkouts(rows: [lift]), now: { t0 })
    model.onChange = { changes += 1 }
    await model.refresh()
    #expect(model.workouts == [lift])
    await model.refresh()
    #expect(changes == 1)   // republish only when the rows changed
    #expect(model.completion(sessionLabel: "Day 1 Full Upper + Z2 40min").isDone)
    #expect(model.completion(sessionLabel: "Rest") == .otherActivity(lift))
}

@MainActor @Test func workoutsFromAnEarlierDayAreNotToday() async {
    var now = t0
    let model = TodayWorkoutsModel(source: StubWorkouts(rows: [lift]), now: { now })
    await model.refresh()
    now = t0.addingTimeInterval(24 * 3600)
    #expect(model.workouts.isEmpty)
    #expect(model.completion(sessionLabel: "Strength") == .none)
}

@Test func matchingStrengthWorkoutMarksTodaysDayDoneAndMovesNext() {
    let w = week().applyingTodayWorkouts([lift])
    #expect(w.days[0].done == true)
    #expect(w.planDone == 1)
    #expect(w.next?.weekday == 2)
    #expect(daySessionOrdinal(w) == nil)   // no "session 1 of 2" once today's is done
}

@Test func nonMatchingWorkoutLeavesTheSessionOpen() {
    let before = week()
    #expect(before.applyingTodayWorkouts([walk]) == before)
    #expect(before.applyingTodayWorkouts([]) == before)
}

@Test func cardioDayDoneDoesNotCountAsAStrengthSession() {
    let sat = week(today: "2026-10-03")
    let w = sat.applyingTodayWorkouts([walk])
    #expect(w.days[5].done == true)
    #expect(w.planDone == sat.planDone)
}

@Test func unknownDoneCountStaysUnknown() {
    let w0 = week()
    let unknown = TrainingWeekSummary(days: w0.days, planTotal: 2, assigned: 2, planDone: nil, next: w0.next)
    let w = unknown.applyingTodayWorkouts([lift])
    #expect(w.days[0].done == true)
    #expect(w.planDone == nil)
}

@Test func plannedKindOfAWeekDay() {
    #expect(week().days[0].plannedSessionKind == .strength)
    #expect(week().days[5].plannedSessionKind == .cardio)
    #expect(week().days[1].plannedSessionKind == .rest)
}

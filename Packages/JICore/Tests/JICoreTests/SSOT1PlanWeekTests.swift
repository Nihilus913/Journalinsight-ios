import Foundation
import Testing
@testable import JICore

// W-SSOT-1 SS-7: `GET /planning/week?start=` — the hub's ONE `session_for` answer for seven days —
// decodes, and `PlanScheduleResolver` prefers it over re-deriving the week from plan-session rows.
// Golden: Resources/ssot1/planning_week.json = HT `tests/fixtures/ssot1/planning_week.json` (L1, 4f8bd19).

private let fixedWeek: [ScheduledSession] = [
    ScheduledSession(name: "Day 1 Full Upper + Z2 40min", kind: .strength),
    ScheduledSession(name: "Norwegian 4x4 intervals", kind: .interval),
    ScheduledSession(name: "Day 2 Full Upper + Z2 60min", kind: .strength),
    ScheduledSession(name: "Long Zone 2 75-90min", kind: .z2),
    ScheduledSession(name: "Day 3 Full Upper + Z2 60min", kind: .strength),
    ScheduledSession(name: "Norwegian 4x4 intervals", kind: .interval),
    ScheduledSession(name: "Rest", kind: .rest),
]

private func weekGolden() throws -> PlanWeekOut {
    let url = try #require(Bundle.module.url(forResource: "planning_week", withExtension: "json", subdirectory: "Resources/ssot1"))
    return try JSON.decoder.decode(PlanWeekOut.self, from: Data(contentsOf: url))
}

@Test func planWeekGoldenDecodesSevenDays() throws {
    let w = try weekGolden()
    #expect(w.start == "2026-10-05")
    #expect(w.days.count == 7)
    #expect(w.days.map(\.weekday) == Array(0...6))
    let tue = w.days[1]
    #expect(tue.date == "2026-10-06" && tue.sessionId == 990002)
    #expect(tue.name == "Interval Run" && tue.sessionType == "cardio")
    #expect(tue.prescription == "Norwegian 4x4 intervals" && tue.type == "interval" && tue.source == "plan")
    #expect(w.days[3].sessionId == nil && w.days[3].type == "rest")
}

@Test func resolverPrefersTheServedWeekOverPlanRows() throws {
    // The rows still say Tue = Day 1 (stale); the served week is the hub's session_for.
    let rows = [PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 1, sessionType: "strength")]
    let r = PlanScheduleResolver(planWeek: try weekGolden(), planSessions: rows, fixedWeek: fixedWeek)
    let week = try #require(r.week)
    #expect(week[0] == ScheduledSession(name: "Day 1 Full Upper + Z2 40min", kind: .strength))
    #expect(week[1] == ScheduledSession(name: "Norwegian 4x4 intervals", kind: .interval))
    #expect(week[2] == ScheduledSession(name: "Day 2 Push + Triceps", kind: .strength))   // not in the fixed table
    #expect(week[3] == ScheduledSession(name: "Rest", kind: .rest))
    let fallback = ScheduledSession(name: "x", kind: .z2)
    #expect(r.session(on: "2026-10-06", weekday: 1, fallback: fallback).kind == .interval)
    #expect(r.servedSession(on: "2026-10-10") == ScheduledSession(name: "Day 4 Chest + Arms", kind: .strength))
    #expect(r.servedSession(on: "2026-10-12") == nil)
    #expect(r.kind(named: "Day 3 Pull + Core") == .strength)
}

@Test func aServedDayWithoutPrescriptionMapsLikeARow() {
    let d = PlanWeekDayOut(date: "2026-10-07", weekday: 2, sessionId: 4, name: "Long Zone 2", sessionType: "cardio",
                           prescription: nil, type: nil)
    #expect(PlanScheduleResolver.session(for: d, fixedWeek: fixedWeek) == ScheduledSession(name: "Long Zone 2 75-90min", kind: .z2))
    let empty = PlanWeekDayOut(date: "2026-10-08", weekday: 3, prescription: nil, type: nil)
    #expect(PlanScheduleResolver.session(for: empty, fixedWeek: fixedWeek).kind == .rest)
}

@Test func resolverFallsBackToPlanRowsWithoutAWeek() {
    let rows = [PlanSessionOut(id: 4, name: "Long Zone 2", weekday: 2, sessionType: "cardio")]
    let r = PlanScheduleResolver(planWeek: nil, planSessions: rows, fixedWeek: fixedWeek)
    #expect(r.week?[2] == ScheduledSession(name: "Long Zone 2 75-90min", kind: .z2))
    #expect(r == PlanScheduleResolver(planSessions: rows, fixedWeek: fixedWeek))
}

@Test func anIncompleteWeekIsNotPreferred() throws {
    let partial = PlanWeekOut(start: "2026-09-28", days: Array(try weekGolden().days.prefix(3)))
    let rows = [PlanSessionOut(id: 3, name: "Day 2 Full Upper", weekday: 2, sessionType: "strength")]
    let r = PlanScheduleResolver(planWeek: partial, planSessions: rows, fixedWeek: fixedWeek)
    #expect(r.week?[2] == ScheduledSession(name: "Day 2 Full Upper + Z2 60min", kind: .strength))
}

@Test func aProviderWithoutTheWeekRouteReportsItUnavailable() async {
    struct Bare: TrainingProviding {
        func trainingDay(date: String) async throws -> TrainingDayDetail { throw PlanWeekUnavailable() }
        func exercises() async throws -> [Exercise] { [] }
        func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult { throw PlanWeekUnavailable() }
    }
    await #expect(throws: PlanWeekUnavailable.self) { _ = try await Bare().planWeek(start: "2026-09-28") }
}

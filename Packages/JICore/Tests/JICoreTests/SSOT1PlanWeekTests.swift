import Foundation
import Testing
@testable import JICore

// W-SSOT-1 SS-7: `GET /planning/week?start=` — the hub's ONE `session_for` answer for seven days —
// decodes, and `PlanScheduleResolver` prefers it over re-deriving the week from plan-session rows.
// PROVISIONAL golden (Resources/ssot1/planning_week.json): written from the card's field names
// before L1 committed the HT route golden; swap for the synced copy when it lands.

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
    #expect(w.start == "2026-09-28")
    #expect(w.days.count == 7)
    #expect(w.days.map(\.weekday) == Array(0...6))
    #expect(w.days[2].date == "2026-09-30")
    #expect(w.days[2].session == "Long Zone 2 75-90min")
    #expect(w.days[2].sessionType == "z2")
}

@Test func planWeekDecodesAlternateSpellingsAndNullSession() throws {
    let json = Data(#"""
    {"start":"2026-09-28","days":[
      {"date":"2026-09-28","weekday":0,"name":"Day 1 Full Upper + Z2 40min","type":"strength"},
      {"date":"2026-09-29","weekday":1,"session":null,"session_type":null}
    ]}
    """#.utf8)
    let w = try JSON.decoder.decode(PlanWeekOut.self, from: json)
    #expect(w.days[0].session == "Day 1 Full Upper + Z2 40min" && w.days[0].sessionType == "strength")
    #expect(w.days[1].session == nil && w.days[1].sessionType == nil)
}

@Test func resolverPrefersTheServedWeekOverPlanRows() throws {
    // The rows still say Wed = Day 2 (stale), the served week already has the move.
    let rows = [PlanSessionOut(id: 3, name: "Day 2 Full Upper", weekday: 2, sessionType: "strength")]
    let r = PlanScheduleResolver(planWeek: try weekGolden(), planSessions: rows, fixedWeek: fixedWeek)
    let week = try #require(r.week)
    #expect(week[2] == ScheduledSession(name: "Long Zone 2 75-90min", kind: .z2))
    #expect(week[3] == ScheduledSession(name: "Day 2 Full Upper + Z2 60min", kind: .strength))
    let fallback = ScheduledSession(name: "x", kind: .rest)
    #expect(r.session(on: "2026-09-30", weekday: 2, fallback: fallback).kind == .z2)
    // A date the served week covers answers by date — even before the rows' changeover rule.
    #expect(r.session(on: "2026-10-04", weekday: 6, fallback: fallback) == ScheduledSession(name: "Rest", kind: .rest))
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

import Foundation
import Testing
@testable import JICore

// W-FIX10 R-01: the app's day → session answer follows plan.plan_session.weekday (what the day
// sheet moves), the same rule as morning_go.py `plan_weekdays_from_rows` / `session_for`.

private let fixedWeek: [ScheduledSession] = [
    ScheduledSession(name: "Day 1 Full Upper + Z2 40min", kind: .strength),
    ScheduledSession(name: "Norwegian 4x4 intervals", kind: .interval),
    ScheduledSession(name: "Day 2 Full Upper + Z2 60min", kind: .strength),
    ScheduledSession(name: "Long Zone 2 75-90min", kind: .z2),
    ScheduledSession(name: "Day 3 Full Upper + Z2 60min", kind: .strength),
    ScheduledSession(name: "Norwegian 4x4 intervals", kind: .interval),
    ScheduledSession(name: "Rest", kind: .rest),
]

private let plan: [PlanSessionOut] = [
    PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 0, sessionType: "strength"),
    PlanSessionOut(id: 2, name: "Interval Run", weekday: 1, sessionType: "cardio"),
    PlanSessionOut(id: 3, name: "Day 2 Full Upper", weekday: 3, sessionType: "strength"),   // moved Wed → Thu
    PlanSessionOut(id: 4, name: "Long Zone 2", weekday: 2, sessionType: "cardio"),              // moved Thu → Wed
    PlanSessionOut(id: 5, name: "Day 3 Full Upper", weekday: 4, sessionType: "strength"),
    PlanSessionOut(id: 6, name: "Interval Run 2", weekday: 5, sessionType: "cardio"),
    PlanSessionOut(id: 7, name: "Day 4 Full Upper", weekday: nil, sessionType: "strength"), // parked
]

@Test func resolverFollowsPlanWeekdaysWithTheTableVocabulary() {
    let r = PlanScheduleResolver(planSessions: plan, fixedWeek: fixedWeek)
    let week = try! #require(r.week)
    #expect(week.count == 7)
    #expect(week[2] == ScheduledSession(name: "Long Zone 2 75-90min", kind: .z2))
    #expect(week[3] == ScheduledSession(name: "Day 2 Full Upper + Z2 60min", kind: .strength))
    #expect(week[1] == ScheduledSession(name: "Norwegian 4x4 intervals", kind: .interval))
    #expect(week[6] == ScheduledSession(name: "Rest", kind: .rest))   // no session on Sunday → rest
}

@Test func resolverUsesThePlanFromTheEffectiveDateAndTheFallbackBefore() {
    let r = PlanScheduleResolver(planSessions: plan, fixedWeek: fixedWeek)
    let fallback = ScheduledSession(name: "Day 2 Full Upper + Z2 60min", kind: .strength)
    // 2026-09-30 is a Wednesday (2).
    #expect(r.session(on: "2026-09-30", weekday: 2, fallback: fallback).kind == .z2)
    // Before PLAN_WEEKDAYS_EFFECTIVE the history keeps the fixed table.
    #expect(r.session(on: "2026-09-23", weekday: 2, fallback: fallback) == fallback)
}

@Test func resolverWithoutPlanRowsIsTheFallback() {
    let empty = PlanScheduleResolver(planSessions: [], fixedWeek: fixedWeek)
    #expect(empty.week == nil)
    let none = PlanScheduleResolver(planSessions: nil, fixedWeek: fixedWeek)
    let fb = ScheduledSession(name: "Rest", kind: .rest)
    #expect(none.session(on: "2026-10-04", weekday: 6, fallback: fb) == fb)
}

@Test func resolverTwoSessionsOnADayTheOwedOneWins() {
    let rows = [
        PlanSessionOut(id: 1, name: "Long Zone 2", weekday: 0, sessionType: "cardio"),
        PlanSessionOut(id: 2, name: "Day 1 Full Upper", weekday: 0, sessionType: "strength"),
        PlanSessionOut(id: 3, name: "Rest", weekday: 1, sessionType: "rest"),
        PlanSessionOut(id: 4, name: "Interval Run", weekday: 1, sessionType: "cardio"),
    ]
    let week = try! #require(PlanScheduleResolver(planSessions: rows, fixedWeek: fixedWeek).week)
    #expect(week[0].kind == .strength)
    #expect(week[1].kind == .interval)
}

@Test func resolverUnknownStrengthNameKeepsItsOwnName() {
    let rows = [PlanSessionOut(id: 9, name: "Day 4 Full Upper", weekday: 5, sessionType: "strength")]
    let week = try! #require(PlanScheduleResolver(planSessions: rows, fixedWeek: fixedWeek).week)
    #expect(week[5] == ScheduledSession(name: "Day 4 Full Upper", kind: .strength))
}

@Test func resolverKindByNameReadsThePlanThenTheTable() {
    let r = PlanScheduleResolver(planSessions: plan, fixedWeek: fixedWeek)
    #expect(r.kind(named: "Long Zone 2 75-90min") == .z2)
    #expect(r.kind(named: "Day 3 Full Upper + Z2 60min") == .strength)
    #expect(r.kind(named: "Something else") == nil)
}

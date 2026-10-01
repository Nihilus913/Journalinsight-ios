import Foundation
import Testing
@testable import JICompute

// W-FIX10 R-01: `session_for(day, plan)` — from PLAN_WEEKDAYS_EFFECTIVE on, the plan's weekdays
// (plan.plan_session, what the day sheet moves) decide the day; the fixed table is the fallback.

private let movedWeek: [GateSession] = [
    sessionByWeekday[0], sessionByWeekday[1],
    GateSession(name: "Long Zone 2 75-90min", type: .z2),           // Wed ← Thu's long run
    GateSession(name: "Day 2 Full Upper + Z2 60min", type: .strength), // Thu ← Wed's lifts
    sessionByWeekday[4], sessionByWeekday[5], sessionByWeekday[6],
]

@Test func sessionForFollowsThePlanFromTheChangeover() throws {
    #expect(planWeekdaysEffective == "2026-09-29")
    #expect(try sessionFor("2026-09-30", plan: movedWeek).type == .z2)          // Wednesday
    #expect(try sessionFor("2026-10-01", plan: movedWeek).type == .strength)    // Thursday
}

@Test func sessionForKeepsTheTableBeforeTheChangeoverAndWithoutAPlan() throws {
    #expect(try sessionFor("2026-09-23", plan: movedWeek) == sessionByWeekday[2])
    #expect(try sessionFor("2026-09-30", plan: nil) == sessionByWeekday[2])
    #expect(try sessionFor("2026-09-30", plan: []) == sessionByWeekday[2])      // malformed plan → table
    #expect(try sessionFor("2026-08-29", plan: movedWeek).type == .optional)    // Saturday legacy intact
}

@Test func evaluateReadsThePlannedSessionFromThePlan() throws {
    let got = try evaluate(today: "2026-09-30", vitals: MorningVitals(), db: MorningGateDb(),
                           state: MorningGatePrevState(), plan: movedWeek)
    #expect(got.verdict.contains("Long Zone 2 75-90min"))
}

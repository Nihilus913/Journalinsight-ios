import Foundation
import Testing
import JICore
import JICompute
@testable import JIFeatures

// W-SSOT-2 S2-4: the app's `JICompute.sessionFor` (fixed table + plan weekdays) agrees with the
// hub's served `/planning/week` — golden 2026-09-30.
//
// Captured read-only from the hub, `GET /api/v1/planning/week?start=2026-09-28`, 2026-10-01.
private let goldenWeekJSON = """
{"start":"2026-09-28","days":[
{"date":"2026-09-28","weekday":0,"session_id":1,"name":"Day 1 Full Upper","session_type":"strength","prescription":"Day 1 Full Upper + Z2 40min","type":"strength","source":"plan"},
{"date":"2026-09-29","weekday":1,"session_id":5,"name":"Interval Run","session_type":"cardio","prescription":"Norwegian 4x4 intervals","type":"interval","source":"plan"},
{"date":"2026-09-30","weekday":2,"session_id":2,"name":"Day 2 Full Upper","session_type":"strength","prescription":"Day 2 Full Upper + Z2 60min","type":"strength","source":"plan"},
{"date":"2026-10-01","weekday":3,"session_id":6,"name":"Long Zone 2","session_type":"cardio","prescription":"Long Zone 2 75-90min","type":"z2","source":"plan"},
{"date":"2026-10-02","weekday":4,"session_id":3,"name":"Day 3 Full Upper","session_type":"strength","prescription":"Day 3 Full Upper + Z2 60min","type":"strength","source":"plan"},
{"date":"2026-10-03","weekday":5,"session_id":8,"name":"Interval Run 2","session_type":"cardio","prescription":"Norwegian 4x4 intervals","type":"interval","source":"plan"},
{"date":"2026-10-04","weekday":6,"session_id":7,"name":"Rest","session_type":"rest","prescription":"Rest","type":"rest","source":"plan"}
]}
"""

private func goldenWeek() throws -> PlanWeekOut {
    try JSON.decoder.decode(PlanWeekOut.self, from: Data(goldenWeekJSON.utf8))
}

/// The same plan as the plan-session rows (`GET /planning/plan-sessions`) the app falls back to.
private func goldenRows(_ w: PlanWeekOut) -> [PlanSessionOut] {
    w.days.compactMap { d in
        d.sessionId.map { PlanSessionOut(id: $0, name: d.name ?? "", weekday: d.weekday, sessionType: d.sessionType) }
    }
}

@Test func golden20260930SessionForMatchesServedWeek() throws {
    let w = try goldenWeek()
    let served = try #require(w.days.first { $0.date == "2026-09-30" })
    // The fixed table (no plan) and the plan weekdays both give the hub's answer.
    let table = try sessionFor("2026-09-30")
    #expect(table.name == served.prescription)
    #expect(table.type.rawValue == served.type)
    let rows = goldenRows(w)
    let fromRows = try #require(scheduledSession(on: "2026-09-30", planSessions: rows))
    #expect(fromRows.name == served.prescription)
    #expect(fromRows.type.rawValue == served.type)
    let fromWeek = try #require(scheduledSession(on: "2026-09-30", planSessions: rows, week: w))
    #expect(fromWeek == fromRows)
}

@Test func goldenWeekEveryDayMatchesServedWeek() throws {
    let w = try goldenWeek()
    let rows = goldenRows(w)
    let plan = plannedWeek(planSchedule(rows))
    for d in w.days {
        // JICompute.sessionFor with the rows' plan weekdays (what the gate evaluates) …
        let gate = try sessionFor(d.date, plan: plan)
        #expect(gate.name == d.prescription, "\(d.date)")
        #expect(gate.type.rawValue == d.type, "\(d.date)")
        // … and with the served week's weekdays.
        let servedGate = try sessionFor(d.date, plan: plannedWeek(planSchedule(nil, week: w)))
        #expect(servedGate == gate, "\(d.date)")
    }
}

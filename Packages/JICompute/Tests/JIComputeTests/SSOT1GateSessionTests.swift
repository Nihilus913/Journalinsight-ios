import Testing
@testable import JICompute

// W-SSOT-1 SS-6 (audit 01-P2): the gate's `(name, type)` value is `GateSession`, so it no longer
// collides with JICore's Codable `PlannedSession(id, name, weekday)` in files importing both.
@Test func gateScheduleIsTypedAsGateSession() throws {
    let monday: GateSession = sessionByWeekday[0]
    #expect(monday == GateSession(name: "Day 1 Full Upper + Z2 40min", type: .strength))
    let resolved: GateSession = try sessionFor("2026-09-28")   // a Monday
    #expect(resolved.type == .strength)
}

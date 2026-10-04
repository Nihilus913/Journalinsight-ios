import Foundation
import Testing
@testable import JICore

// W-B88 B88-5 (ONE workout model, slice 1): after HT migration 073 every workout the hub lists is a
// template. A strength day is its library template (t5…t8, sport "strength", linked_refs ["s<id>"],
// editable false). Fixture: Resources/planner/planning_workouts_b88.json = HT
// tests/fixtures/planning_workouts.json (the post-073 golden, B88-3).

private func b88Fixture() throws -> [PlannerWorkout] {
    let url = try #require(Bundle.module.url(forResource: "planning_workouts_b88", withExtension: "json", subdirectory: "Resources/planner"))
    return try JSON.decoder.decode([PlannerWorkout].self, from: Data(contentsOf: url))
}

@Test func b88EveryRowIsATemplateAndAStrengthDayNamesItsSession() throws {
    let rows = try b88Fixture()
    #expect(rows.count == 8 && rows.allSatisfy { $0.kind == .template })
    let day1 = try #require(rows.first { $0.ref == "t5" })
    #expect(day1.name == "Day 1 Full Upper" && day1.isStrength && !day1.editable && day1.liftCount == 6)
    #expect(day1.templateId == 5 && day1.sessionId == nil && day1.linkedSessionIds == [1])
    #expect(day1.strengthSessionId == 1)
    #expect(rows.first { $0.ref == "t8" }?.weekdays == [])
    // a cardio template's linked sessions are not "strength sessions"
    #expect(rows.first { $0.ref == "t3" }?.strengthSessionId == nil)
    #expect(plannerSessionTemplateLinks(rows) == [1: 5, 2: 6, 3: 7, 4: 8, 5: 3, 6: 1, 8: 3])
}

@Test func b88ASessionRowIsItsOwnStrengthSession() {
    let s = PlannerWorkout(ref: "s4", kind: .planSession, name: "Day 4 Full Upper", sport: "strength", weekdays: [], liftCount: 6, editable: false)
    #expect(s.strengthSessionId == 4)
}

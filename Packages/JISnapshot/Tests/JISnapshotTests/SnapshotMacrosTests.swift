import Foundation
import Testing
import JICore
@testable import JISnapshot

// B-57 W2 C4 (B-73): "Left to your goals" for KpiWidget medium/inline. Goals are test values a
// user typed; JI ships none.

@Test func leftIsGoalMinusEatenNeverBelowZero() throws {
    let m = try #require(SnapshotMacros.make(goals: (1800, 155, 144, 49), eatenToday: (650, 52, 160, nil), healthReadable: true, asOf: nil))
    #expect(m.kcal == SnapshotMacro(goal: 1800, left: 1150))
    #expect(m.protein == SnapshotMacro(goal: 155, left: 103))
    #expect(m.carbs == SnapshotMacro(goal: 144, left: 0))      // over goal → 0 left, never negative
    #expect(m.fat == SnapshotMacro(goal: 49, left: 49))        // nothing logged yet today
}

/// Review Focus 2: Health not readable → no macros, so the widget never shows "1617 left".
@Test func unreadableHealthOrNoGoalsGivesNil() {
    #expect(SnapshotMacros.make(goals: (1800, 155, 144, 49), eatenToday: (nil, nil, nil, nil), healthReadable: false, asOf: nil) == nil)
    #expect(SnapshotMacros.make(goals: (nil, nil, nil, nil), eatenToday: (100, 10, 10, 10), healthReadable: true, asOf: nil) == nil)
}

/// Unset goals are omitted, not zero: no "left" line for them.
@Test func unsetGoalIsOmittedNotZero() throws {
    let m = try #require(SnapshotMacros.make(goals: (nil, 160, nil, nil), eatenToday: (650, 52, 60, 10), healthReadable: true, asOf: nil))
    #expect(m.kcal == nil)
    #expect(m.carbs == nil)
    #expect(m.protein == SnapshotMacro(goal: 160, left: 108))
    #expect(m.inlineText(for: .kcal) == nil)
    #expect(m.inlineText(for: .carbs) == nil)
}

@Test func inlineTextMatchesTheBoard() throws {
    let m = try #require(SnapshotMacros.make(goals: (1800, 155, 144, 49), eatenToday: (650, 52, 160, 10), healthReadable: true, asOf: nil))
    #expect(m.inlineText(for: .protein) == "Protein 103 g to goal")
    #expect(m.inlineText(for: .kcal) == "1150 kcal to goal")
    #expect(m.inlineText(for: .carbs) == "Carbs goal met")
    #expect(m.inlineText(for: .hrv) == nil)
}

@Test func snapshotRoundTripsWithMacrosAndOldPayloadsStillDecode() throws {
    let macros = SnapshotMacros.make(goals: (1800, 155, 144, 49), eatenToday: (650, 52, 60, 10), healthReadable: true, asOf: Date(timeIntervalSince1970: 100))
    let snap = HubSnapshot(verdictWord: "GO", verdictSession: "Full Upper", verdictTone: "go", verdictDate: "2026-09-24",
                           readiness: 70, kpis: [], fetchedAt: Date(timeIntervalSince1970: 0), lastSync: nil, macros: macros)
    let data = try JSONEncoder().encode(snap)
    #expect(try JSONDecoder().decode(HubSnapshot.self, from: data) == snap)

    let old = #"{"verdictWord":"GO","verdictSession":"s","verdictTone":"go","kpis":[],"fetchedAt":0}"#
    #expect(try JSONDecoder().decode(HubSnapshot.self, from: Data(old.utf8)).macros == nil)
}

import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-FIX11 H2-02 (bug hunt 2026-10-01): the weight goal took 7,977.5 kg. Every goal has a
// plausible range (the hub's GOAL_RANGES, same numbers); outside it Save is off and says why.

private func draft(_ m: GoalMetric, _ text: String) -> TargetEditDraft {
    var d = TargetEditDraft(subject: .goal(m), document: .empty)
    d.goalText = text
    return d
}

@Test func weightGoalOutsideTheRangeIsRefused() {
    let d = draft(.weight, "7,977.5")
    #expect(d.validationMessage == "Weight: between 20 and 400 kg.")
    guard case .failure(.invalid) = d.applied(to: .empty) else { Issue.record("saved 7977.5 kg"); return }
}

@Test func everyGoalHasARange() {
    let cases: [(GoalMetric, String)] = [(.weight, "5"), (.kcal, "99999"), (.protein, "5000"), (.carbs, "9000"),
                                         (.fat, "2000"), (.steps, "1000000"), (.sleep, "30")]
    for (m, text) in cases { #expect(draft(m, text).validationMessage != nil, "\(m)") }
    let ok: [(GoalMetric, String)] = [(.weight, "74"), (.kcal, "1935"), (.protein, "185"), (.carbs, "172"),
                                      (.fat, "59"), (.steps, "12000"), (.sleep, "7.5")]
    for (m, text) in ok { #expect(draft(m, text).validationMessage == nil, "\(m)") }
}

@Test func rangesMatchTheHub() {
    #expect(TargetsGoalRange.range(.weight) == 20...400)
    #expect(TargetsGoalRange.range(.kcal) == 500...10000)
    #expect(TargetsGoalRange.range(.steps) == 100...100000)
    #expect(TargetsGoalRange.range(.sleep) == 1...16)
}

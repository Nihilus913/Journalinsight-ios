import Testing
@testable import JIFeatures

/// RG-51: More's Goals row "80.2 → 75.0 kg" read like a current weight next to My KPIs' newest
/// weigh-in 79.5 (19 Sep). The row now says it is the goal's start → goal, dated by the goal's date.
@Suite struct RG51WeightGoalLabelTests {
    @Test func startToGoalIsLabelledAndDated() {
        let v = moreGoalsStartValue(startKg: 80.24, targetKg: 75, targetDate: "2026-10-31")
        #expect(v.text == "Start 80.2 → goal 75.0 kg · by 31 Oct")
    }

    @Test func undatedGoalHasNoDateTail() {
        #expect(moreGoalsStartValue(startKg: 80.2, targetKg: 75, targetDate: nil).text == "Start 80.2 → goal 75.0 kg")
    }

    @Test func missingStartOrGoalKeepsTheOldFallbacks() {
        #expect(moreGoalsStartValue(startKg: nil, targetKg: 75, targetDate: nil).text == "— → goal 75.0 kg")
        #expect(moreGoalsStartValue(startKg: 80.2, targetKg: nil, targetDate: nil, otherGoals: 2).text == "2 goals set")
        #expect(moreGoalsStartValue(startKg: 80.2, targetKg: nil, targetDate: nil).text == "— No goal set")
    }
}

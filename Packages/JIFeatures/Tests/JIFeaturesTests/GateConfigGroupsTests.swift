import Testing
@testable import JIFeatures

// W-TGT L3: Gate thresholds merged into Settings › Targets (spec §4). What stays of GateConfig is
// "How the morning call works" (+ the walk-through); the Garmin knob is a Targets rule, not a goal.
struct GateConfigGroupsTests {
    @Test func garminSleepKnobIsARuleNotTheSleepGoal() {
        #expect(targetsRuleTitle(.intervalMinSleep) == "Garmin nights · interval floor")
        #expect(!targetsRuleExplanation(.intervalMinSleep).lowercased().contains("goal"))
    }

    @Test func morningCallCardIsFullModifiedRest() {
        #expect(gateConfigMorningCallRows.map(\.word) == ["Full", "Modified", "Rest"])
    }

    @Test func theScreenPointsToTargetsForTheNumbers() {
        #expect(gateConfigTitle == "How the morning call works")
        #expect(gateConfigFooter.contains("Settings › Targets"))
    }
}

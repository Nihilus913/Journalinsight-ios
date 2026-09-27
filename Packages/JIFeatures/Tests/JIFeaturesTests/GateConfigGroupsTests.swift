import Testing
import JIDesign
@testable import JIFeatures

struct GateConfigGroupsTests {
    @Test func fieldsLandInTheBoardGroups() {
        #expect(MorningGateOverridableField.minSleepH.group == .recoverySignals)   // B-57 W3: Garmin knob, not the goal
        #expect(MorningGateOverridableField.respDeltaAmber.group == .recoverySignals)
        #expect(MorningGateOverridableField.carb3dWatch.group == .fuel)
        for f in [MorningGateOverridableField.kcalTarget, .proteinTarget, .carbTarget, .fatTarget, .stepTarget, .targetWeight, .targetBf] {
            #expect(f.group == nil)   // "Calorie, protein and weight targets live in Goals."
        }
    }

    @Test func everyShownFieldHasAOneLineExplanation() {
        for f in MorningGateOverridableField.allCases where f.group != nil { #expect(!f.explanation.isEmpty) }
    }

    @Test func garminSleepKnobIsNotTheSleepGoal() {
        #expect(MorningGateOverridableField.minSleepH.label == "Garmin nights: min sleep for intervals")   // B-57 W3
        #expect(!MorningGateOverridableField.minSleepH.explanation.lowercased().contains("goal"))
    }

    @Test func morningCallCardIsFullModifiedRest() {
        #expect(gateConfigMorningCallRows.map(\.word) == ["Full", "Modified", "Rest"])
    }
}

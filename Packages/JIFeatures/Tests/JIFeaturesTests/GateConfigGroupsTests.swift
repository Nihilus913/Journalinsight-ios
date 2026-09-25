import Testing
import JIDesign
@testable import JIFeatures

struct GateConfigGroupsTests {
    @Test func fieldsLandInTheBoardGroups() {
        #expect(MorningGateOverridableField.minSleepH.group == .sleep)
        #expect(MorningGateOverridableField.respDeltaAmber.group == .recoverySignals)
        #expect(MorningGateOverridableField.carb3dWatch.group == .fuel)
        for f in [MorningGateOverridableField.kcalTarget, .proteinTarget, .carbTarget, .fatTarget, .stepTarget, .targetWeight, .targetBf] {
            #expect(f.group == nil)   // "Calorie, protein and weight targets live in Goals."
        }
    }

    @Test func everyShownFieldHasAOneLineExplanation() {
        for f in MorningGateOverridableField.allCases where f.group != nil { #expect(!f.explanation.isEmpty) }
    }

    @Test func sleepStaysFloorWordedInW1() {
        #expect(MorningGateOverridableField.minSleepH.label == "Min sleep (interval gate)")
        #expect(!MorningGateOverridableField.minSleepH.explanation.lowercased().contains("goal"))
    }

    @Test func morningCallCardIsFullModifiedRest() {
        #expect(gateConfigMorningCallRows.map(\.word) == ["Full", "Modified", "Rest"])
    }
}

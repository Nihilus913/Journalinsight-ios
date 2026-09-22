import SwiftUI
import Testing
@testable import JIDesign

@Test func macroRingsAccessibilityLabelListsAllThree() {
    let label = macroRingsAccessibilityLabel(
        protein: MacroRingValue(value: 120, goal: 160), carbs: MacroRingValue(value: 210.4, goal: 250), fat: MacroRingValue(value: 55, goal: 70))
    #expect(label == "Protein 120 of 160 grams, Carbs 210 of 250 grams, Fat 55 of 70 grams")
}

@Test @MainActor func macroRingsRender() {
    expectRenders("MacroRings", width: 100, height: 100) {
        MacroRings(protein: .init(value: 120, goal: 160), carbs: .init(value: 210, goal: 250), fat: .init(value: 55, goal: 70))
    }
}

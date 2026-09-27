import SwiftUI
import Testing
@testable import JIDesign

struct HowWeCalculateTests {
    private let steps = [HowWeCalculateStep(title: "Burned = resting + active energy", body: "Both read from Apple Health."),
                         HowWeCalculateStep(title: "Eaten = dietary energy", body: "Written there by YAZIO.")]

    @Test func stepsAreNumberedForVoiceOver() {
        #expect(howWeCalculateStepAccessibilityLabel(index: 0, count: 2, step: steps[0])
                == "Step 1 of 2. Burned = resting + active energy. Both read from Apple Health.")
    }

    @Test func stepIdsAreStableAndUnique() {
        #expect(Set(steps.map(\.id)).count == steps.count)
    }

    @Test @MainActor func renders() {
        expectRenders("HowWeCalculate", height: 360) { HowWeCalculate(title: "How we calculate", steps: steps, note: "No medical judgement.") }
        // W-B57-W5 fixer: no NavigationStack under ImageRenderer (see GlassButtonTests).
        expectRenders("HowWeCalculateLink", height: 60) { HowWeCalculateLink(title: "How we calculate", steps: steps) }
    }
}

import SwiftUI
import Testing
@testable import JIDesign

struct HowWeCalculateTests {
    private let steps = [HowWeCalculateStep(title: "Burned = resting + active energy", body: "Both read from Apple Health."),
                         HowWeCalculateStep(title: "Eaten = dietary energy", body: "Written there by YAZIO.")]

    @Test func stepIdsAreStableAndUnique() {
        #expect(Set(steps.map(\.id)).count == steps.count)
    }

    @Test @MainActor func renders() {
        expectRenders("HowWeCalculate", height: 360) { HowWeCalculate(title: "How we calculate", steps: steps, note: "No medical judgement.") }
    }
}

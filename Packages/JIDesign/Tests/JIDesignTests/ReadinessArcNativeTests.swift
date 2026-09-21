import SwiftUI
import Testing
@testable import JIDesign

// §4: fill arc runs from SwiftUI 180° (9 o'clock) to 180° + 1.8°·score. Classic maths untouched.
@Test(arguments: [(0.0, 180.0), (50.0, 270.0), (100.0, 360.0), (140.0, 360.0)])
func fillEndAngleFollowsScore(score: Double, degrees: Double) {
    #expect(gaugeFillEndAngle(for: score).degrees == degrees)
}

@Test func classicGaugeMathsUnchanged() {
    #expect(gaugeAngle(for: 50).degrees == 360)
    #expect(readinessBand(for: 70) == .go)
}

@Test @MainActor func gaugeRendersEveryStateInBothThemes() {
    expectRenders("score", width: 200, height: 120) { ReadinessArcGauge(score: 72) }
    expectRenders("no data", width: 200, height: 120) { ReadinessArcGauge(score: nil) }
    expectRenders("source missing", width: 200, height: 120) { ReadinessArcGauge(score: 72, sourceMissing: true) }
}

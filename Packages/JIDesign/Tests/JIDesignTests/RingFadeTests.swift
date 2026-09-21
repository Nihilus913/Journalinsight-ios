import SwiftUI
import Testing
@testable import JIDesign

// B-33 §4: the long fade — α 0 at the start, ≈0.12 at a third, ≈0.45 at two thirds, 1 at the head.
@Test(arguments: [(0.0, 0.0), (1.0 / 3, 0.12), (2.0 / 3, 0.45), (1.0, 1.0), (-1.0, 0.0), (2.0, 1.0)])
func fadeOpacityHitsTheKnots(t: Double, alpha: Double) {
    #expect(abs(ringFadeOpacity(at: t) - alpha) < 1e-9)
}

@Test func fadeOpacityIsMonotonic() {
    var last = -1.0
    for i in 0...100 {
        let a = ringFadeOpacity(at: Double(i) / 100)
        #expect(a >= last); last = a
    }
}

@Test func fadeStopsSpanZeroToOne() {
    let stops = ringFadeStops(.red, samples: 8)
    #expect(stops.count == 9)
    #expect(stops.first?.location == 0 && stops.last?.location == 1)
}

@Test(arguments: [(50.0, 100.0, 0.5), (120.0, 100.0, 1.0), (-3.0, 100.0, 0.0), (5.0, 0.0, 0.0)])
func ringFractionClamps(value: Double, max: Double, fraction: Double) {
    #expect(ringFraction(value: value, max: max) == fraction)
}

@Test func ringAccessibilityValueReadsNOfMax() {
    #expect(ringAccessibilityValue(value: 72.4, max: 100) == "72 of 100")
}

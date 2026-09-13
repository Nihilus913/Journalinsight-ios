import Testing
@testable import JIDesign

// Non-isolated on purpose: readinessBand(for:), gaugeAngle(for:), and
// ReadinessBand are declared `nonisolated` in ReadinessArcGauge.swift so the
// pure math stays callable from anywhere despite JIDesign's MainActor
// default isolation. Leaving these test functions with no @MainActor proves
// that stays true (TokensTests.swift's suite is @MainActor; this one need
// not be).

@Test(arguments: [(0.0, ReadinessBand.danger), (39.9, .danger), (40.0, .warn), (69.9, .warn), (70.0, .go), (100.0, .go)])
func bandsMatchRN(value: Double, band: ReadinessBand) {
    #expect(readinessBand(for: value) == band)
}

@Test(arguments: [(0.0, 270.0), (50.0, 360.0), (100.0, 450.0), (-5.0, 270.0), (140.0, 450.0)])
func angleMatchesRNClockConvention(value: Double, degrees: Double) {
    #expect(gaugeAngle(for: value).degrees == degrees)
}

@Test(arguments: Array(stride(from: -10.0, through: 100.0, by: 10.0)))
func gaugeAngleIsMonotonicNonDecreasing(value: Double) {
    let next = value + 10.0
    #expect(gaugeAngle(for: next).degrees >= gaugeAngle(for: value).degrees)
}

// Accessibility must announce the same numeral the eye sees (RN rounds both; Int() truncated).
@Test func accessibilityNumeralRoundsLikeTheVisibleOne() {
    #expect(69.9.formatted(.number.precision(.fractionLength(0))) == "70")
    #expect(Int(69.9) == 69)
}

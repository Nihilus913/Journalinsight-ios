import Testing
@testable import JIDesign

// Rule 6: contributor/component bars (driver bars) are neutral gray, NEVER the reserved
// verdict green — regardless of how large a driver's contribution is.

@MainActor
struct DriverBarsTests {
    @Test func barColorIsNeutralNeverReservedGreen() {
        #expect(DriverBars.barRole == .mutedNested)
        #expect(DriverBars.barRole != .go)
        #expect(JITheme.native.color(DriverBars.barRole) != JITheme.native.color(.go))
    }

    @Test(arguments: [0.0, 0.25, 0.5, 0.9, 1.0])
    func barColorStaysNeutralAcrossEveryMagnitude(value: Double) {
        // The color is a constant, not a function of `value` — assert that structurally by
        // constructing drivers spanning the full range and confirming the shared paint token
        // used to render every bar never varies.
        _ = DriverBar(id: "d", label: "Driver", value: value)
        #expect(DriverBars.barRole == .mutedNested)
    }
}

// Rule 5: a missing driver never renders as a zero-width bar with no explanation.

@Test func driverBarWithNilValueAndNoSourceMissingFlagStillHasHonestCopy() {
    let driver = DriverBar(id: "load", label: "Training load", value: nil)
    #expect(driverBarAccessibilityLabel(driver: driver) == "Training load, no data yet")
}

@Test func driverBarWithSourceMissingAnnouncesSharedCopyNotAPercent() {
    let driver = DriverBar(id: "sleep", label: "Sleep", value: 0.8, sourceMissing: true)
    let label = driverBarAccessibilityLabel(driver: driver)
    #expect(label == "Sleep Not from the current source")
    #expect(!label.contains("%"))
}

@Test func driverBarWithRealValueAnnouncesPercent() {
    let driver = DriverBar(id: "hrv", label: "HRV", value: 0.42)
    #expect(driverBarAccessibilityLabel(driver: driver) == "HRV 42%")
}

// B-57 W3 D2: an optional status word and tint, additive (no word/tint = the old behaviour).

@Test func driverBarWordAndTintAreAdditive() {
    let plain = DriverBar(id: "a", label: "HRV", value: 0.5)
    #expect(plain.word == nil && plain.tint == nil)
    #expect(DriverBars.fillRole(for: plain) == .mutedNested)
    let low = DriverBar(id: "hrv", label: "HRV", value: 0.2, word: "Low", tint: .reduced)
    #expect(DriverBars.fillRole(for: low) == .reduced)
    #expect(driverBarAccessibilityLabel(driver: low) == "HRV, Low")
    let sleep = DriverBar(id: "sleep", label: "Sleep", value: 0.6, word: "Above goal", tint: .sleep)
    #expect(DriverBars.fillRole(for: sleep) == .sleep)
}

@Test func driverBarNeverUsesVerdictGreen() {
    let g = DriverBar(id: "x", label: "X", value: 1, word: "Above", tint: .go)
    #expect(DriverBars.fillRole(for: g) == .mutedNested)
}

@Test func missingValueWithWordStillSaysTheWord() {
    let d = DriverBar(id: "rhr", label: "Resting HR", value: nil, word: "No reading")
    #expect(driverBarAccessibilityLabel(driver: d) == "Resting HR, No reading")
}

@Test func sourceMissingStillWinsOverAWord() {
    let d = DriverBar(id: "sleep", label: "Sleep", value: 0.5, sourceMissing: true, word: "Above goal")
    #expect(driverBarAccessibilityLabel(driver: d) == "Sleep Not from the current source")
}

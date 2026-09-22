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

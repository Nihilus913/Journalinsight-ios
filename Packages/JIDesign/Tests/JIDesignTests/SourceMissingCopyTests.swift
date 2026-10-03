import Testing
@testable import JIDesign

// DESIGN-6: sourceMissing == true must announce "Not from the current source", never a
// bare unit with no numeral and never the dash alone. Exercised against the pure label
// builders extracted from StatChip/ReadinessArcGauge/DriverBars/EAGatedTile so the
// assertion holds independent of SwiftUI's view lifecycle. Non-isolated on purpose, like
// GaugeMathTests — these builders are declared `nonisolated`.

@Test func readinessGaugeSourceMissingAnnouncesSharedCopy() {
    let label = readinessAccessibilityLabel(score: nil, sourceMissing: true)
    #expect(label == "Readiness Not from the current source")
    #expect(!label.contains("—"))
}

@Test func readinessGaugeMissingCopyMatchesStatChipCopyExactly() {
    // Both components must speak with one voice (DESIGN-6): same literal copy, not a
    // near-miss like "no data" or "not available".
    #expect(sourceMissingCopy == "Not from the current source")
}

@Test func driverBarSourceMissingAnnouncesSharedCopy() {
    let driver = DriverBar(id: "sleep", label: "Sleep", value: nil, sourceMissing: true)
    let label = driverBarAccessibilityLabel(driver: driver)
    #expect(label == "Sleep Not from the current source")
}

@Test func eaGatedTileDefaultsToSharedCopy() {
    let label = eaGatedTileAccessibilityLabel(label: "Energy availability", reason: sourceMissingCopy)
    #expect(label == "Energy availability, Not from the current source")
}

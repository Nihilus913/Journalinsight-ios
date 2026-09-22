import SwiftUI
import Testing
@testable import JIDesign

@Test func summaryCardLabelReadsTitleValueUnitTimestamp() {
    #expect(summaryCardAccessibilityLabel(title: "HRV", value: "52", unit: "ms", timestamp: "Today, 07:12", sourceMissing: false) == "HRV 52 ms, Today, 07:12")
}

@Test func summaryCardLabelWithoutValueSaysNoData() {
    #expect(summaryCardAccessibilityLabel(title: "HRV", value: nil, unit: "ms", timestamp: nil, sourceMissing: false) == "HRV, no data yet")
}

@Test func summaryCardLabelSourceMissingUsesSharedCopy() {
    #expect(summaryCardAccessibilityLabel(title: "Body Battery", value: nil, unit: nil, timestamp: nil, sourceMissing: true) == "Body Battery \(sourceMissingCopy)")
}

@Test @MainActor func summaryCardRenders() {
    expectRenders("SummaryCard") {
        SummaryCard(icon: "waveform.path.ecg", tint: .red, title: "HRV", value: "52", unit: "ms", timestamp: "Today, 07:12", sparkline: [48, 50, 47, 53, 51, 49, 52], action: {})
    }
    expectRenders("SummaryCard gated") {
        SummaryCard(icon: "battery.75percent", tint: .teal, title: "Body Battery", value: nil, sourceMissing: true)
    }
}

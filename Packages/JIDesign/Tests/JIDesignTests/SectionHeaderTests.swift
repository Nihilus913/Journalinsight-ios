import SwiftUI
import Testing
@testable import JIDesign

// W-GUI S2 (report §4.5): 13 pt bold caps, inset 16, 24 above / 8 below.
@Test func sectionHeaderTitleIsCaps() {
    #expect(sectionHeaderTitle("Drivers") == "DRIVERS")
    #expect(sectionHeaderTitle("Your call for today") == "YOUR CALL FOR TODAY")
    #expect(sectionHeaderTitle("") == "")
}

@Test func sectionHeaderMetricsMatchTheReport() {
    #expect(JISectionHeaderMetrics.inset == 16)
    #expect(JISectionHeaderMetrics.above == 24 && JISectionHeaderMetrics.below == 8)
    #expect(JITypography.size(.footnote) == 13)
}

@Test @MainActor func sectionHeaderRenders() {
    expectRenders("JISectionHeader") { JISectionHeader("Drivers") }
}

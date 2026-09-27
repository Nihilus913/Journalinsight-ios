import SwiftUI
import Testing
@testable import JIDesign

// W-GUI F9 — the disclosure row (report §4.5 "Row").
@Test func chevronRowMetricsMatchTheReport() {
    #expect(JIChevronRowMetrics.minHeight == 56)
    #expect(JIChevronRowMetrics.verticalPadding == 12)
    #expect(JIChevronRowMetrics.iconWell == 32 && JIChevronRowMetrics.iconWellRadius == 10)
    #expect(JIChevronRowMetrics.chevron == "chevron.right")
}

@Test @MainActor func chevronRowRendersAtLeast56() {
    let row = JIChevronRow(title: "Settings", value: "Hub synced 07:41", systemImage: "slider.horizontal.3")
        .frame(width: 361).jiTheme(.native)
    let renderer = ImageRenderer(content: row)
    let height = renderer.cgImage.map { CGFloat($0.height) / renderer.scale } ?? 0
    #expect(height >= JIChevronRowMetrics.minHeight, "row is \(height) pt")
    expectRenders("JIChevronRow custom label") { JIChevronRow { Text("My KPIs") } }
}

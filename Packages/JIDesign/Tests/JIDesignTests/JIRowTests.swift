import SwiftUI
import Testing
@testable import JIDesign

// W-GUI S2 (report §4.5): rows are 56 pt minimum with a 32 pt icon well (r 10), 12 pt vertical.
@Test func rowMetricsMatchTheReport() {
    #expect(JIRow<EmptyView>.minHeight == 56)
    #expect(JIRowMetrics.verticalPadding == 12)
    #expect(JIRowMetrics.iconWell == 32 && JIRowMetrics.iconWellRadius == 10)
    #expect(JIRowMetrics.hairlineInset == 44)
}

@Test @MainActor func rowRendersAtLeast56() {
    let row = JIRow(title: "Sleep score", subtitle: "Last night", systemImage: "bed.double.fill", tint: .purple) { Text("85") }
        .frame(width: 361).jiTheme(.native)
    let r = ImageRenderer(content: row)
    let h = r.cgImage.map { CGFloat($0.height) / r.scale } ?? 0
    #expect(h >= JIRowMetrics.minHeight, "row is \(h) pt")
    expectRenders("JIRow plain") { JIRow(title: "Version") }
}

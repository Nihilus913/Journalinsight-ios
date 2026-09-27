import SwiftUI
import Testing
@testable import JIDesign

// W-GUI F9 — 52 pt buttons, radius 18, black on the accent (BUG-30), one primary per screen.
@Test func buttonMetricsMatchTheReport() {
    #expect(JIButtonMetrics.height == 52 && JIButtonMetrics.height == JITileHeight.button.base)
    #expect(JIButtonMetrics.radius == 18)
    #expect(JIButtonMetrics.primaryLabel == .black)
}

@Test @MainActor func buttonsRenderAtTheirHeight() {
    let primary = Button("Go with this") {}.buttonStyle(.jiPrimary).frame(width: 361).jiTheme(.native)
    let r = ImageRenderer(content: primary)
    let h = r.cgImage.map { CGFloat($0.height) / r.scale } ?? 0
    #expect(h >= JIButtonMetrics.height && h < JIButtonMetrics.height + 4, "primary is \(h) pt")
    expectRenders("secondary") { Button("Adjust") {}.buttonStyle(.jiSecondary) }
    expectRenders("primary disabled") { Button("Go") {}.buttonStyle(.jiPrimary).disabled(true) }
}

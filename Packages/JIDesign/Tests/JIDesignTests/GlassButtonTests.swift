import SwiftUI
import Testing
@testable import JIDesign

// W-GUI F5 — the 44 pt glass round button (report §4.5, §7 rule 2).

@Test func glassButtonIs44AndChevronOnly() {
    #expect(JIGlassButtonMetrics.side == 44)
    #expect(JIGlassButtonMetrics.side == JITileHeight.glassButton.base)
    for s in ["chevron.left", "pencil", "calendar", "plus"] { #expect(JIGlassButtonMetrics.isAllowed(s)) }
    #expect(!JIGlassButtonMetrics.isAllowed("heart.fill"))
    #expect(!JIGlassButtonMetrics.isAllowed(""))
}

@MainActor
@Test func glassButtonRendersInGlassAndOpaque() {
    expectRenders("JIGlassButton") { JIGlassButton("chevron.left", label: "Back") {} }
    expectRenders("JIGlassButton RT") { JIGlassButton("plus", label: "Add") {}.jiAccessibilityOverrides(reduceTransparency: true) }
    expectRenders("jiGlassBackButton") { NavigationStack { Text("pushed").jiGlassBackButton() } }
}

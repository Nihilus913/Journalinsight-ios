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
    // W-B57-W5 fixer: no NavigationStack under ImageRenderer — it cannot flatten the UIKit
    // representable and the iOS run died on SwiftUI's "no current update to enqueue action to".
    expectRenders("jiGlassBackButton") { Text("pushed").jiGlassBackButton() }
}

import SwiftUI
import Testing
@testable import JIDesign

// W-GUI F7 — the nested tile family (report §4.5: one fixed height per family, DEV-06).
@Test func tileFamiliesAreTheReportHeights() {
    #expect(JITileHeight.tile.base == 96 && JITileHeight.macroTile.base == 96)
    #expect(JITileHeight.factTile.base == 64 && JITileHeight.statCard.base == 120)
    #expect(surfaceStyle(level: 2, theme: .native).material == false)   // no glass on glass
}

@Test @MainActor func tilesRender() {
    expectRenders("JITile") { JITile(family: .macroTile) { Text("98 g") } }
    expectRenders("JITile tinted") { JITile(family: .factTile, tint: .blue) { Text("7 h 40") } }
    expectRenders("JIAddTile") { JIAddTile(family: .catalogSquare, label: "Add a square") {} }
    expectRenders("SummaryCard square") { SummaryCard(icon: "heart.fill", tint: .red, title: "Resting HR", value: "54", unit: "bpm", timestamp: "as of 26 Sep", action: {}) }
    expectRenders("SummaryCard AX3", height: 400) {
        SummaryCard(icon: "heart.fill", tint: .red, title: "Resting HR", value: "54", unit: "bpm", timestamp: "as of 26 Sep", action: {})
            .environment(\.dynamicTypeSize, .accessibility3)
    }
}

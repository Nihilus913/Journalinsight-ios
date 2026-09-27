import SwiftUI
import Testing
@testable import JIDesign

// §8.1: 2 columns on an iPhone, 4 inside a 720-pt readable column, never 0.
@Test(arguments: [(361.0, 2), (408.0, 2), (720.0, 4), (924.0, 5), (100.0, 1), (0.0, 1)])
func columnCountMatchesAdaptiveArithmetic(width: Double, count: Int) {
    #expect(columnCount(availableWidth: width, minimum: 160, spacing: 12) == count)
}

@Test func columnCountSurvivesZeroMinimum() {
    #expect(columnCount(availableWidth: 400, minimum: 0, spacing: 12) == 1)
}

@Test func adaptiveAxisIsHorizontalOnlyInRegularWidth() {
    #expect(adaptiveAxis(.regular) == .horizontal)
    #expect(adaptiveAxis(.compact) == .vertical)
}

@Test @MainActor func layoutViewsRender() {
    expectRenders("Columns") { Columns(minimum: 120) { ForEach(0..<4) { Text("\($0)") } } }
    expectRenders("AdaptiveHStack") { AdaptiveHStack { Text("a"); Text("b") } }
    expectRenders("readableColumn", width: 900) { Text("wide").readableColumn() }
}

// W-GUI F7 (DEV-06): `Columns(tileHeight:)` fixes every cell to the family height.
@Test @MainActor func columnsWithTileHeightRender() {
    expectRenders("Columns tileHeight", width: 393, height: 400) {
        Columns(minimum: 160, tileHeight: .square) { ForEach(0..<4) { Text("tile \($0)") } }
    }
    expectRenders("Columns tileHeight AX3", width: 393, height: 800) {
        Columns(minimum: 160, tileHeight: .statCard) { Text("a"); Text("b") }.environment(\.dynamicTypeSize, .accessibility3)
    }
}

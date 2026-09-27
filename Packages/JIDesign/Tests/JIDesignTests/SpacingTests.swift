import SwiftUI
import Testing
@testable import JIDesign

// W-GUI F1 — report §4.5 layout tokens. Pure, nonisolated.

@Test func spacingScaleIsTheSixStepScale() {
    #expect(JISpacing.s1 == 4)
    #expect(JISpacing.s2 == 8)
    #expect(JISpacing.s3 == 12)
    #expect(JISpacing.s4 == 16)
    #expect(JISpacing.s6 == 24)
    #expect(JISpacing.s8 == 32)
    #expect(JISpacing.cardGap == 12)
    #expect(JISpacing.tileGap == 8)
    #expect(JISpacing.cardPadding == 16)
    #expect(JISpacing.tilePadding == 12)
    #expect(JISpacing.sideMargin == 16)
    // Every derived token sits on the scale — nothing else (§4.5).
    let scale: Set<CGFloat> = [4, 8, 12, 16, 24, 32]
    for v in [JISpacing.cardGap, JISpacing.tileGap, JISpacing.cardPadding, JISpacing.tilePadding, JISpacing.sideMargin] {
        #expect(scale.contains(v))
    }
}

@Test func tileHeightFamiliesAreTheFixedBaseValues() {
    #expect(JITileHeight.square.base == 172)
    #expect(JITileHeight.tile.base == 96)
    #expect(JITileHeight.catalogSquare.base == 104)
    #expect(JITileHeight.statCard.base == 120)
    #expect(JITileHeight.factTile.base == 64)
    #expect(JITileHeight.macroTile.base == 96)
    #expect(JITileHeight.row.base == 56)
    #expect(JITileHeight.button.base == 52)
    #expect(JITileHeight.glassButton.base == 44)
    #expect(JITileHeight.allCases.count == 9)
}

@Test func radiusMappingIsConcentric() {
    // 26 − 8 (card padding − tile padding … the §4.5 concentric rule) = 18; control 12.
    #expect(JITheme.native.radius(.card) == 26 && JITheme.native.radius(.nested) == 18 && JITheme.native.radius(.control) == 12)
    #expect(JITheme.native.radius(.card) - 8 == JITheme.native.radius(.nested))
}

@MainActor
@Test func scaledTileModifierRenders() {
    expectRenders("jiTileHeight(.square)") { Color.red.jiTileHeight(.square) }
    expectRenders("jiTileHeight(.factTile)") { Text("x").jiTileHeight(.factTile) }
}

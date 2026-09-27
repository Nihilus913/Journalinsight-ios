import SwiftUI
import Testing
@testable import JIDesign

// B-33 §2: inset grouped cells (26 / 18 / 12). Pure, nonisolated. Phase C deleted the classic
// radii (`JIRadius`) and the classic level-3 fill with the language that used them.

@Test func nativeRadiiMatchTheSpec() {
    #expect(JITheme.native.radius(.hero) == 26)
    #expect(JITheme.native.radius(.card) == 26)
    #expect(JITheme.native.radius(.nested) == 18)
    #expect(JITheme.native.radius(.control) == 12)
}

@Test(arguments: [(1, JIColorRole.surface, JIRadiusRole.card), (2, .surface2, .nested), (3, .control, .control), (9, .surface, .card)])
func nativeSurfaceLevelsMapToFillAndRadius(level: Int, fill: JIColorRole, radius: JIRadiusRole) {
    let s = surfaceStyle(level: level, theme: .native)
    #expect(s.fill == fill && s.radius == radius)
}

// W-GUI F2 — report §4.1/4.2 depth recipe.

@Test func onlyLevelOneCarriesTheMaterial() {
    #expect(surfaceStyle(level: 1, theme: .native).material == true)
    #expect(surfaceStyle(level: 2, theme: .native).material == false)
    #expect(surfaceStyle(level: 3, theme: .native).material == false)
    let l1 = JISurfaceRecipe.resolve(level: 1, reduceTransparency: false, increasedContrast: false, colorScheme: .dark)
    let l2 = JISurfaceRecipe.resolve(level: 2, reduceTransparency: false, increasedContrast: false, colorScheme: .dark)
    #expect(l1.material && !l1.opaque && l1.shadowOpacity == 0.55 && l1.shadowY == 10 && l1.shadowRadius == 14)
    #expect(!l2.material && l2.opaque && l2.shadowOpacity == 0 && l2.hairlineOpacity == 0)
    #expect(l1.rimTop == 0.22 && l1.rimMid == 0.05 && l1.rimBottom == 0.03 && l1.rimWidth == 1)
    #expect(l2.rimTop == 0.05 && l2.highlightOpacity == 0.08)
}

@Test func reduceTransparencyForcesOpaque() {
    let r = JISurfaceRecipe.resolve(level: 1, reduceTransparency: true, increasedContrast: false, colorScheme: .dark)
    #expect(r.opaque && !r.material)
}

@Test func increaseContrastUsesTheThickUniformRim() {
    for level in 1...2 {
        let r = JISurfaceRecipe.resolve(level: level, reduceTransparency: false, increasedContrast: true, colorScheme: .dark)
        #expect(r.rimWidth == 1.5)
        #expect(r.rimTop == 0.35 && r.rimMid == 0.35 && r.rimBottom == 0.35)
    }
}

@Test func lightModeRimsAreDark() {
    let r = JISurfaceRecipe.resolve(level: 1, reduceTransparency: false, increasedContrast: false, colorScheme: .light)
    #expect(r.rimIsDark && r.rimTop == 0.08 && r.rimBottom == 0.03 && r.fillOpacity == 0.60)
}

@MainActor
@Test func surfaceRendersNestedAndUnderFallbacks() {
    expectRenders("level 1 in level 2") {
        Surface(level: 2) { Surface(level: 1) { Text("nested") } }
    }
    expectRenders("tinted hero") { Surface(tint: .green) { Text("hero") } }
    expectRenders("reduce transparency") {
        Surface { Text("rt") }.jiAccessibilityOverrides(reduceTransparency: true)
    }
    expectRenders("increase contrast") {
        Surface { Text("ic") }.jiAccessibilityOverrides(increaseContrast: true)
    }
}

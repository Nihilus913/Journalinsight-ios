import Testing
@testable import JIDesign

// B-33 §2: native = inset grouped cells (26 / 18 / 12), classic unchanged. Pure, nonisolated.
@Test func nativeRadiiMatchTheSpec() {
    #expect(JITheme.native.radius(.hero) == 26)
    #expect(JITheme.native.radius(.card) == 26)
    #expect(JITheme.native.radius(.nested) == 18)
    #expect(JITheme.native.radius(.control) == 12)
}

@Test func classicRadiiAreTheExistingTokens() {
    #expect(JITheme.classic.radius(.hero) == JIRadius.hero)
    #expect(JITheme.classic.radius(.card) == JIRadius.card)
}

@Test(arguments: [(1, JIColorRole.surface, JIRadiusRole.card), (2, .surface2, .nested), (3, .control, .control), (9, .surface, .card)])
func nativeSurfaceLevelsMapToFillAndRadius(level: Int, fill: JIColorRole, radius: JIRadiusRole) {
    let s = surfaceStyle(level: level, theme: .native)
    #expect(s.fill == fill && s.radius == radius)
}

@Test func classicLevel3KeepsSurface3() {
    #expect(surfaceStyle(level: 3, theme: .classic).fill == .surface3)
}

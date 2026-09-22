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

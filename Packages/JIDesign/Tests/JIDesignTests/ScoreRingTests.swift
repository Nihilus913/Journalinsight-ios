import SwiftUI
import Testing
@testable import JIDesign

@Test @MainActor func scoreRingRenders() {
    expectRenders("ScoreRing", width: 80, height: 80) { ScoreRing(value: 72, max: 100, tint: .purple) }
    expectRenders("ScoreRing empty", width: 80, height: 80) { ScoreRing(value: 0, max: 0, tint: .purple) }
}

@Test func scoreRingDefaultSizeIs44() {
    #expect(ScoreRing.defaultSize == 44)
}

// W-GUI F8 — the ring glow token (report §4.2): 6 pt at 40 %, off under Increase Contrast.
@Test func ringGlowTokenAndContrastRule() {
    #expect(JIRingGlow.radius == 6 && JIRingGlow.opacity == 0.4)
    #expect(JIRingGlow.radius(increasedContrast: false) == 6)
    #expect(JIRingGlow.radius(increasedContrast: true) == 0)
}

@Test @MainActor func glowingRingsRender() {
    expectRenders("ScoreRing glow") { ScoreRing(value: 72, max: 100, tint: .blue).jiRevealAnimations(false) }
    expectRenders("ScoreRing IC") { ScoreRing(value: 72, max: 100, tint: .blue).jiRevealAnimations(false).jiAccessibilityOverrides(increaseContrast: true) }
    expectRenders("MacroRings glow") { MacroRings(protein: .init(value: 120, goal: 160), carbs: .init(value: 210, goal: 250), fat: .init(value: 55, goal: 70)).jiRevealAnimations(false) }
    expectRenders("Readiness glow") { ReadinessArcGauge(score: 72).jiRevealAnimations(false) }
}

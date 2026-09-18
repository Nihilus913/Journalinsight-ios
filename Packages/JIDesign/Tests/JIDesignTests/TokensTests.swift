import SwiftUI
import Testing
import JICore
@testable import JIDesign

@MainActor
struct TokensTests {
    @Test func verdictTonesMapToReservedColors() {
        #expect(JIColor.color(for: .go) == JIColor.go)
        #expect(JIColor.color(for: .amber) == JIColor.reduced)
        #expect(JIColor.color(for: .red) == JIColor.danger)
        #expect(JIColor.color(for: .muted) == JIColor.muted)
    }

    @Test func pressScaleClearsPerceptionThreshold() {
        // ≥ 8 % region change (feedback_feel_is_a_story rule 6): 0.92² = 0.846 → 15.4 % area change.
        #expect(PressableScaleStyle.pressedScale <= 0.92)
    }

    @Test func hexParsesExactly() {
        // Independently hand-computed from the RN token spec (mobile/src/theme/tokens.ts,
        // CONTEXT-IOS-FOUNDATION.md L204): bg = 0x0b0f14 → r=11/255, g=15/255, b=20/255.
        // W5a-L1: `JIColor.bg` is dynamic (dark/light) — resolve it under the dark scheme, which is
        // what this pre-W5a expectation always described (see TokensLightTests for the light ramp).
        var env = EnvironmentValues()
        env.colorScheme = .dark
        let resolved = JIColor.bg.resolve(in: env)
        #expect(abs(Double(resolved.red) - 11.0 / 255.0) < 0.001)
        #expect(abs(Double(resolved.green) - 15.0 / 255.0) < 0.001)
        #expect(abs(Double(resolved.blue) - 20.0 / 255.0) < 0.001)
    }

    @Test func motionDurationsMatchRNTokens() {
        #expect(JIMotion.micro == .milliseconds(200))
        #expect(JIMotion.card == .milliseconds(400))
    }
}

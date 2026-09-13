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
        #expect(Color(hex: 0x0b0f14) == JIColor.bg)
    }

    @Test func motionDurationsMatchRNTokens() {
        #expect(JIMotion.micro == .milliseconds(200))
        #expect(JIMotion.card == .milliseconds(400))
    }
}

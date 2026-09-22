import SwiftUI
import Testing
import JICore
@testable import JIDesign

// B-33 Phase C deleted the RN-era hex ramps (`JIPalette`, the `JIColor` statics) that this suite
// used to pin. What survives here is what is NOT a colour token: the press-in scale and the
// motion durations. The semantic identity of the surviving native roles is asserted in
// NativePaletteTests.swift; the reserved-colour rule in SleepCardTests / DriverBarsTests /
// ContributorBreakdownTests, which now compare roles.

@MainActor
struct TokensTests {
    @Test func verdictTonesMapToReservedRoles() {
        // The tone -> role map is the one thing the deleted `JIColor.color(for:)` encoded that
        // still has meaning: `go` is the reserved verdict green, and nothing else resolves to it.
        #expect(JITheme.native.color(.go) != JITheme.native.color(.reduced))
        #expect(JITheme.native.color(.go) != JITheme.native.color(.danger))
        #expect(JITheme.native.color(.go) != JITheme.native.color(.muted))
    }

    @Test func pressScaleClearsPerceptionThreshold() {
        // >= 8 % region change (feedback_feel_is_a_story rule 6): 0.92^2 = 0.846 -> 15.4 % area change.
        #expect(PressableScaleStyle.pressedScale <= 0.92)
    }

    @Test func motionDurationsMatchRNTokens() {
        #expect(JIMotion.micro == .milliseconds(200))
        #expect(JIMotion.card == .milliseconds(400))
    }
}

import SwiftUI
import Testing
@testable import JIDesign

// B-33 §8.0 — the per-screen theme switch. Phase C removed `.classic`, so `.native` is the
// only language and the environment default.
@MainActor
struct JIThemeTests {
    @Test func defaultThemeIsNative() {
        #expect(EnvironmentValues().jiTheme == .native)
    }

    @Test func themeCanBeSetOnTheEnvironment() {
        var env = EnvironmentValues()
        env.jiTheme = .native
        #expect(env.jiTheme == .native)
    }

    // B-33 F1: the sweep/snapshot switch that makes rings + arc paint their FINAL value.
    @Test func revealAnimationsDefaultOnAndCanBeTurnedOff() {
        #expect(EnvironmentValues().jiRevealAnimations == true)
        var env = EnvironmentValues()
        env.jiRevealAnimations = false
        #expect(env.jiRevealAnimations == false)
    }

    @Test func nativeIsTheOnlyLanguage() {
        // Persisted nowhere, but ~40 screens hard-code `.native`; keep the name.
        #expect(JITheme.allCases.map(\.rawValue) == ["native"])
    }
}

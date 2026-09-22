import SwiftUI
import Testing
@testable import JIDesign

// B-33 §8.0 — the per-screen theme switch. Default is classic so the 37 old screens never change.
@MainActor
struct JIThemeTests {
    @Test func defaultThemeIsClassic() {
        #expect(EnvironmentValues().jiTheme == .classic)
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

    @Test func rawValuesAreStable() {
        // Persisted nowhere yet, but B-40b screens hard-code `.native`; keep the names.
        #expect(JITheme.allCases.map(\.rawValue) == ["classic", "native"])
    }
}

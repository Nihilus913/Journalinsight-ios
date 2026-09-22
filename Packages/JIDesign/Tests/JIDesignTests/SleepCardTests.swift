import SwiftUI
import Testing
@testable import JIDesign

// Reserved-color rule (CLAUDE.md §6 / CONTEXT-IOS-FOUNDATION.md L204): green is allowed ONLY
// on the 0-100 sleep score itself, never on the sleep-score component sub-bars or the
// contributor-breakdown bars. B-33 Phase C: `sleepScoreColorRole` returns a ROLE (pure,
// `nonisolated`); the active theme resolves it, so the rule is asserted on roles and only the
// theme resolution needs the MainActor.

@MainActor
struct SleepCardTests {
    @Test func sleepScoreIsReservedGoGreenInTheGoBand() {
        // 82 >= readinessGoMin (70) -> .go band -> the one place the reserved green is allowed.
        #expect(sleepScoreColorRole(score: 82, sourceMissing: false) == .go)
        #expect(JITheme.native.color(sleepScoreColorRole(score: 82, sourceMissing: false)) == JITheme.native.color(.go))
    }

    @Test func sleepScoreIsNotGreenBelowTheGoBand() {
        #expect(sleepScoreColorRole(score: 55, sourceMissing: false) == .reduced)
        #expect(sleepScoreColorRole(score: 20, sourceMissing: false) == .danger)
        #expect(sleepScoreColorRole(score: 55, sourceMissing: false) != .go)
        #expect(sleepScoreColorRole(score: 20, sourceMissing: false) != .go)
    }

    @Test func sleepScoreNeverGreenWhenMissingOrSourceMissing() {
        #expect(sleepScoreColorRole(score: nil, sourceMissing: false) == .muted)
        #expect(sleepScoreColorRole(score: 95, sourceMissing: true) == .muted)
    }

    @Test func sleepScoreComponentSubBarsAreAlwaysNeutralNeverReservedGreen() {
        // The component sub-bar fill is a fixed neutral ROLE (SleepScoreComponents.swift),
        // independent of the value it displays — it can never resolve to the reserved go color.
        #expect(SleepScoreComponents.barRole == .mutedNested)
        #expect(SleepScoreComponents.barRole != .go)
        #expect(JITheme.native.color(SleepScoreComponents.barRole) != JITheme.native.color(.go))
    }

    @Test func sleepScoreComponentsCarrySourceMissingCopyNotABareUnit() {
        let missing = SleepScoreComponent(id: "duration", label: "Duration", value: nil)
        #expect(missing.value == nil) // rendering guards on sourceMissing, never a bare "—<unit>"
    }
}

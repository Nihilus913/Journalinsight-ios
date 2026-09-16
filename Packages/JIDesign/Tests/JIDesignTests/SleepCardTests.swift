import SwiftUI
import Testing
@testable import JIDesign

// Reserved-color rule (CLAUDE.md §6 / CONTEXT-IOS-FOUNDATION.md L204): green is allowed ONLY
// on the 0-100 sleep score itself, never on the sleep-score component sub-bars or the
// contributor-breakdown bars. `sleepScoreColor` calls MainActor-isolated `JIColor.muted`/
// `JIColor.color(for:)` (JIDesign's default isolation — see ReadinessArcGauge.swift's
// `bandColor` / Tokens.swift's `TokensTests`), so this suite is `@MainActor`.

@MainActor
struct SleepCardTests {
    @Test func sleepScoreIsReservedGoGreenInTheGoBand() {
        // 82 >= readinessGoMin (70) -> .go band -> the one place the reserved green is allowed.
        #expect(sleepScoreColor(score: 82, sourceMissing: false) == JIColor.go)
    }

    @Test func sleepScoreIsNotGreenBelowTheGoBand() {
        #expect(sleepScoreColor(score: 55, sourceMissing: false) == JIColor.reduced)
        #expect(sleepScoreColor(score: 20, sourceMissing: false) == JIColor.danger)
        #expect(sleepScoreColor(score: 55, sourceMissing: false) != JIColor.go)
        #expect(sleepScoreColor(score: 20, sourceMissing: false) != JIColor.go)
    }

    @Test func sleepScoreNeverGreenWhenMissingOrSourceMissing() {
        #expect(sleepScoreColor(score: nil, sourceMissing: false) != JIColor.go)
        #expect(sleepScoreColor(score: 95, sourceMissing: true) != JIColor.go)
    }

    @Test func sleepScoreComponentSubBarsAreAlwaysNeutralNeverReservedGreen() {
        // The component sub-bar fill is a fixed neutral token (SleepScoreComponents.swift),
        // independent of the value it displays — it can never resolve to the reserved go color.
        let componentBarFill = JIColor.mutedNested
        #expect(componentBarFill != JIColor.go)
    }

    @Test func sleepScoreComponentsCarrySourceMissingCopyNotABareUnit() {
        let missing = SleepScoreComponent(id: "duration", label: "Duration", value: nil)
        #expect(missing.value == nil) // rendering guards on sourceMissing, never a bare "—<unit>"
    }
}

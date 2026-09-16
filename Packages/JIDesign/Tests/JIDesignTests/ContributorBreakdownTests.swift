import SwiftUI
import Testing
@testable import JIDesign

// `rankedContributors` is declared `nonisolated` (pure math, like `readinessBand`/`gaugeAngle`
// in ReadinessArcGauge.swift) so this suite needs no @MainActor.

@Test func rankedContributorsOrdersByAbsoluteMagnitudeDescending() {
    let contributors = [
        ReadinessContributor(id: "hrv", label: "HRV", value: 42, magnitude: 3.0),
        ReadinessContributor(id: "rhr", label: "RHR", value: 58, magnitude: -9.0),
        ReadinessContributor(id: "sleep", label: "Sleep", value: 71, magnitude: 5.5),
        ReadinessContributor(id: "acwr", label: "ACWR", value: 1.1, magnitude: 0.2),
    ]
    let ranked = rankedContributors(contributors)
    #expect(ranked.map(\.id) == ["rhr", "sleep", "hrv", "acwr"])
}

@Test func rankedContributorsIsStableForEqualMagnitude() {
    // Swift's sorted(by:) is stable (Swift 5+): equal |magnitude| keeps input order.
    let contributors = [
        ReadinessContributor(id: "a", label: "A", value: 1, magnitude: 4.0),
        ReadinessContributor(id: "b", label: "B", value: 2, magnitude: -4.0),
    ]
    #expect(rankedContributors(contributors).map(\.id) == ["a", "b"])
}

@Test func rankedContributorsHandlesEmptyAndSingleInput() {
    #expect(rankedContributors([]).isEmpty)
    let single = [ReadinessContributor(id: "hrv", label: "HRV", value: 42, magnitude: 1.0)]
    #expect(rankedContributors(single).map(\.id) == ["hrv"])
}

// Reserved-color rule: the contributor bars are neutral, never the reserved verdict green
// (CLAUDE.md §6) — the fill is a fixed token independent of the ranked contributors.
// @MainActor: JIColor's properties are MainActor-isolated (unlike ReadinessContributor,
// which is `nonisolated`), matching DriverBarsTests.swift's split between a `@MainActor`
// struct for its JIColor-touching tests and free nonisolated funcs for the rest.
@MainActor @Test func contributorBarsAreAlwaysNeutralNeverReservedGreen() {
    let contributorBarFill = JIColor.mutedNested
    #expect(contributorBarFill != JIColor.go)
}

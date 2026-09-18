import Foundation
import Testing
import JICompute
@testable import JIFeatures

// W5b-L3 (P-gate-config). Port of the RN oracle's
// `mobile/__tests__/compute/gateConfigPreview.test.ts`, case for case.
//
// E12-8 acceptance: "editing a threshold changes the verdict computed against a fixed fixture row
// in the same session." These are pinned at the compute layer (no SwiftUI, no GRDB) so nothing
// screen-related can break them.

@Test func bundledPreviewFixtureIsATuesdayAnIntervalDay() throws {
    #expect(GatePreviewFixture.bundled.today == "2026-08-25")
    #expect(try sessionFor(GatePreviewFixture.bundled.today).name == "Norwegian 4x4 intervals")
}

@Test func withNoOverridesTheFixtureRowPassesTheIntervalGate() throws {
    let result = try previewMorningGateVerdict(MorningGateOverrides())
    #expect(result.verdict == "GO — Norwegian 4x4 intervals")
}

@Test func raisingMinSleepPastTheFixtureSleepFlipsTheVerdictToModified() throws {
    let result = try previewMorningGateVerdict(MorningGateOverrides(["MIN_SLEEP_H": 6.5]))
    #expect(result.verdict == "MODIFIED — swap intervals for easy Z2 30-40min")
    #expect(result.conditions.joined(separator: " ").contains("Interval gate failed"))
}

@Test func anOverrideAtExactlyTheFixtureDurationStillPasses() throws {
    // `>=`, not `>`.
    let result = try previewMorningGateVerdict(MorningGateOverrides(["MIN_SLEEP_H": 6.2]))
    #expect(result.verdict == "GO — Norwegian 4x4 intervals")
}

@Test func loweringMinSleepBackBelowTheFixtureValueKeepsItGo() throws {
    let result = try previewMorningGateVerdict(MorningGateOverrides(["MIN_SLEEP_H": 5.0]))
    #expect(result.verdict == "GO — Norwegian 4x4 intervals")
}

@Test func anUnrelatedOverrideDoesNotChangeThisFixtureVerdict() throws {
    let result = try previewMorningGateVerdict(MorningGateOverrides(["STEP_TARGET": 20000]))
    #expect(result.verdict == "GO — Norwegian 4x4 intervals")
}

// MARK: - The fixture JSON of record

/// `Fixtures/gate_config_preview_day.json` (repo root) is the card's named artefact;
/// `GatePreviewFixture.bundled` is the same day inline (the library ships no resource bundle, and
/// the RN oracle keeps its fixture inline too). This is what catches the two drifting apart.
///
/// The test target reads its own byte copy, `Tests/JIFeaturesTests/GateConfigFixtures/
/// gate_config_preview_day.json`: the simulator's test host cannot read the repo root under
/// `~/Documents` (macOS privacy prompt → the test hangs), and SwiftPM copies a symlinked resource
/// as a dangling link. Keep the two files identical (`cp Fixtures/gate_config_preview_day.json
/// Packages/JIFeatures/Tests/JIFeaturesTests/GateConfigFixtures/`).
@Test func theBundledFixtureMatchesTheJsonOfRecord() throws {
    let url = try #require(Bundle.module.url(forResource: "gate_config_preview_day", withExtension: "json", subdirectory: "GateConfigFixtures"))
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(GatePreviewFixture.self, from: data)
    #expect(decoded == GatePreviewFixture.bundled)
    // And the JSON day evaluates to the same verdict as the inline one.
    #expect(try previewMorningGateVerdict(MorningGateOverrides(), fixture: decoded).verdict
        == "GO — Norwegian 4x4 intervals")
}

// MARK: - applyMorningGateOverrides / resettability

@Test func applyingNoOverridesReturnsTheCompiledDefaults() {
    #expect(applyMorningGateOverrides(MorningGateOverrides()) == MorningGateConfig.default)
}

@Test func clearingTheOnlyOverrideRestoresTheDefaultConfig() {
    let edited = MorningGateOverrides().setting(.minSleepH, to: 9.0)
    #expect(applyMorningGateOverrides(edited).minSleepH == 9.0)
    let reset = edited.clearing(.minSleepH)
    #expect(reset.isEmpty)
    #expect(applyMorningGateOverrides(reset) == MorningGateConfig.default)
}

@Test func integerTypedConstantsNarrowBackToInt() {
    let config = applyMorningGateOverrides(MorningGateOverrides().setting(.kcalTarget, to: 2050))
    #expect(config.kcalTarget == 2050)
    #expect(config.stepTarget == MorningGateConfig.default.stepTarget)
}

@Test func overridesRoundTripThroughJsonAsAnObject() throws {
    let overrides = MorningGateOverrides().setting(.minSleepH, to: 6.5).setting(.targetBf, to: 15)
    let data = try JSONEncoder().encode(overrides)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.hasPrefix("{"))
    #expect(text.contains("MIN_SLEEP_H"))
    #expect(try JSONDecoder().decode(MorningGateOverrides.self, from: data) == overrides)
}

@Test func everyOverridableFieldReadsAndWritesItsOwnConstant() {
    for field in MorningGateOverridableField.allCases {
        let base = field.value(in: .default)
        let config = applyMorningGateOverrides(MorningGateOverrides().setting(field, to: base + 1))
        #expect(field.value(in: config) == base + 1, "\(field.rawValue) did not round-trip")
    }
}

// MARK: - KPI rule overrides

@Test func kpiRuleKeyDisambiguatesTheThreeAcwrRows() {
    let keys = defaultKpiRules.map { kpiRuleKey($0) }
    #expect(Set(keys).count == defaultKpiRules.count)
    #expect(keys.contains("acwr:>"))
    #expect(keys.contains("acwr:between"))
}

@Test func applyKpiRuleOverridesChangesOnlyThresholdsAndOnlyTheKeyedRow() {
    let key = "acwr:>"
    let rules = applyKpiRuleOverrides(KpiRuleOverrides().setting(key, threshold: 1.45))
    let edited = try! #require(rules.first { kpiRuleKey($0) == key })
    #expect(edited.threshold == 1.45)
    #expect(edited.description == defaultKpiRules.first { kpiRuleKey($0) == key }?.description)
    #expect(edited.operator == ">")
    // Every other row is untouched.
    for rule in rules where kpiRuleKey(rule) != key {
        #expect(rule.threshold == defaultKpiRules.first { kpiRuleKey($0) == kpiRuleKey(rule) }?.threshold)
    }
}

@Test func clearingAKpiRuleOverrideRestoresTheSeededDefaults() {
    let overrides = KpiRuleOverrides().setting("acwr:>", threshold: 9.9)
    #expect(applyKpiRuleOverrides(overrides.clearing("acwr:>")) == defaultKpiRules)
}

@Test func kpiRuleStepMatchesTheOracle() {
    #expect(kpiRuleStep(metric: "acwr") == 0.05)
    #expect(kpiRuleStep(metric: "avg_kcal_7d") == 25)
    #expect(kpiRuleStep(metric: "sleep_score_7d") == 5)
}

@Test func gateConfigFormatMatchesFmtNum() {
    #expect(gateConfigFormat(6) == "6")
    #expect(gateConfigFormat(6.2) == "6.2")
    #expect(gateConfigFormat(15000) == "15000")
    #expect(gateConfigFormat(1.3) == "1.3")
}

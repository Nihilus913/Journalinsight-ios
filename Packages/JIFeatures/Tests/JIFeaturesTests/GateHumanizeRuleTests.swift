import Foundation
import Testing
import JICore
@testable import JIFeatures

/// Port of the oracle `mobile/__tests__/lib/humanizeRule.test.ts` (RN v1.18.2), case for case.
/// The fixtures are the ACTUAL rule strings HT's `evaluate_kpi_gates()` builds
/// (`app/planning/service.py`) against the seeded `kpi_target` rows — nested parens included.
///
/// `en_US` is passed explicitly: RN's `toLocaleString(undefined, …)` reads the ambient locale, which
/// jest fixes to en_US and a Swift test runner does not (see `GateHumanizeRule`'s header).
private let en = Locale(identifier: "en_US")

@Test func avgKcal7dChronicUnderfuelingWithCountQualifier() {
    let rule = "avg_kcal_7d 1235.8 vs threshold 1600.0 (REDUCE: chronic underfueling (5+ of 7 days))"
    let out = GateHumanizeRule.humanize(rule, locale: en)
    #expect(out == "7-day intake averages 1,236 kcal against the 1,600 kcal floor (5+ of 7 days) — chronic underfueling.")
    #expect(!out.contains("avg_kcal_7d"))
}

@Test func avgProtein7dInsufficientProtein() {
    let rule = "avg_protein_7d 118.0 vs threshold 130.0 (REDUCE: insufficient protein (5+ of 7 days))"
    let out = GateHumanizeRule.humanize(rule, locale: en)
    #expect(out == "7-day protein averages 118g against the 130g floor (5+ of 7 days) — insufficient protein.")
    #expect(!out.contains("avg_protein_7d"))
}

@Test func sleepScore7dPoorSleepQuality() {
    let rule = "sleep_score_7d 48.0 vs threshold 55.0 (REDUCE: poor sleep quality (4+ of 7 days))"
    let out = GateHumanizeRule.humanize(rule, locale: en)
    #expect(out == "7-day sleep score averages 48 against the 55 floor (4+ of 7 days) — poor sleep quality.")
    #expect(!out.contains("sleep_score_7d"))
}

@Test func acwrOverTheReduceCeilingReadsAbove() {
    let out = GateHumanizeRule.humanize("acwr 1.35 vs threshold 1.3 (REDUCE: overreaching risk)", locale: en)
    #expect(out == "Training load ratio (ACWR) is 1.35 — above the 1.30 line — overreaching risk.")
}

@Test func acwrUnderTheMaintainFloorReadsBelow() {
    let out = GateHumanizeRule.humanize("acwr 0.75 vs threshold 0.8 (MAINTAIN: undertraining)", locale: en)
    #expect(out == "Training load ratio (ACWR) is 0.75 — below the 0.80 line — undertraining.")
}

@Test func ruleWithoutNestedParenQualifierStillParsesCleanly() {
    let out = GateHumanizeRule.humanize("avg_protein_7d 118.0 vs threshold 130.0 (REDUCE: insufficient protein)", locale: en)
    #expect(out == "7-day protein averages 118g against the 130g floor — insufficient protein.")
}

@Test func unknownMetricFallsBackToACleanedSentence() {
    let out = GateHumanizeRule.humanize("avg_body_battery 45.0 vs threshold 40.0 (REDUCE: low recovery capacity)", locale: en)
    #expect(out == "Avg body battery is 45.0 vs the 40.0 threshold — low recovery capacity.")
    #expect(!out.contains("avg_body_battery"))
}

@Test func missingValueDegradesToAnEmDashNotNaN() {
    let out = GateHumanizeRule.humanize("avg_kcal_7d ? vs threshold 1600.0 (REDUCE: chronic underfueling)", locale: en)
    #expect(!out.contains("NaN"))
    #expect(out.contains("—"))
}

@Test func malformedStringReturnsACleanedSentenceWithNoBareUnderscores() {
    let out = GateHumanizeRule.humanize("garbage_not_a_rule_string", locale: en)
    #expect(!out.contains("_"))
    #expect(!out.isEmpty)
    #expect(out == "Garbage not a rule string")
}

@Test func emptyStringDoesNotThrow() {
    #expect(GateHumanizeRule.humanize("", locale: en).isEmpty)
}

// MARK: - actionForTriggeredRules (oracle src/lib/insight.ts, exercised by
// __tests__/gateRationale/gateRationaleScreen.render.test.tsx's hotfix-#3 case)

private func gate(recommendation: GateRecommendation, rules: [String], suggestions: [String],
                  tracked: Int = 6, total: Int = 7, minTracked: Int = 4) throws -> GateResponse {
    var g = try JSON.decoder.decode(GateResponse.self, from: Data(contentsOf: #require(MockDataProvider.fixtureURL(named: "planning_gate"))))
    g.recommendation = recommendation
    g.triggeredRules = rules
    g.suggestions = suggestions
    g.trackedDays = tracked; g.totalDays = total; g.minTrackedDays = minTracked
    return g
}

@Test func aRealSuggestionAlwaysWinsOverTheDerivedAction() throws {
    let g = try gate(recommendation: .reduce,
                     rules: ["avg_kcal_7d 1235.8 vs threshold 1600.0 (REDUCE: chronic underfueling (5+ of 7 days))"],
                     suggestions: ["Front-load protein earlier in the day"])
    #expect(GateInsight.actionForTriggeredRules(g) == "Front-load protein earlier in the day")
}

@Test func aTriggeredRuleWithNoSuggestionsDerivesTheMetricsAction() throws {
    let g = try gate(recommendation: .reduce,
                     rules: ["avg_kcal_7d 1235.8 vs threshold 1600.0 (REDUCE: chronic underfueling (5+ of 7 days))"],
                     suggestions: [])
    #expect(GateInsight.actionForTriggeredRules(g)
            == "bring kcal back up toward goal — this is chronic under-fueling, not a plateau")
}

@Test func acwrsActionStaysDirectionAgnosticOnAMaintainDay() throws {
    let g = try gate(recommendation: .maintain, rules: ["acwr 0.75 vs threshold 0.8 (MAINTAIN: undertraining)"], suggestions: [])
    #expect(GateInsight.actionForTriggeredRules(g) == "bring training load back toward the target range this week")
}

@Test func anUnknownMetricFallsBackToTheDefaultAction() throws {
    let g = try gate(recommendation: .reduce, rules: ["avg_body_battery 45.0 vs threshold 40.0 (REDUCE: low)"], suggestions: [])
    #expect(GateInsight.actionForTriggeredRules(g) == GateInsight.defaultAction)
}

@Test func noRulesAndNoSuggestionsAlsoFallsBackToTheDefaultAction() throws {
    let g = try gate(recommendation: .progress, rules: [], suggestions: [])
    #expect(GateInsight.actionForTriggeredRules(g) == GateInsight.defaultAction)
}

/// The oracle's non-greedy `[^)]*` gap, ported deliberately: a nested-paren description yields no
/// reason. Pinned so a future "fix" is a conscious divergence from RN, not an accident.
@Test func parseTriggeredRuleKeepsTheOraclesNestedParenGap() {
    let nested = GateInsight.parseTriggeredRule("avg_kcal_7d 1235.8 vs threshold 1600.0 (REDUCE: chronic underfueling (5+ of 7 days))")
    #expect(nested.metric == "avg_kcal_7d")
    #expect(nested.reason == nil)
    let flat = GateInsight.parseTriggeredRule("avg_protein_7d 118.0 vs threshold 130.0 (REDUCE: insufficient protein)")
    #expect(flat.reason == "insufficient protein")
}

@Test func trackedDaysLineAndRecommendationLabels() throws {
    let g = try gate(recommendation: .insufficientData, rules: [], suggestions: [], tracked: 1, total: 8, minTracked: 4)
    #expect(GateInsight.trackedDaysLine(g) == "1 of 8 days tracked · needs 4")
    #expect(GateInsight.recommendationLabel(.insufficientData) == "Not enough tracked days yet for a recommendation")
    #expect(GateInsight.recommendationLabel(.reduce) == "Gate recommends REDUCE")
    #expect(GateInsight.recommendationLabel(.progress) == "Gate recommends PROGRESS")
    #expect(GateInsight.recommendationLabel(.maintain) == "Gate recommends MAINTAIN")
}

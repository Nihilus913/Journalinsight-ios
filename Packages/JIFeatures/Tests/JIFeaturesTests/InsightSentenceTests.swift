import Testing
import Foundation
@testable import JIFeatures
import JICore

/// B-42 — the RN oracle's `mobile/__tests__/insight.test.ts` ported case for case. The DTOs'
/// memberwise inits are internal to JICore, so every fixture is decoded from wire JSON with the
/// hub's own decoder (same idiom as `NativeFixtureStore.decode`).
@Suite struct InsightSentenceTests {
    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) -> T {
        try! JSON.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func gate(recommendation: String = "MAINTAIN",
                      triggeredRules: [String] = [],
                      suggestions: [String] = [],
                      averages: String = #"{"trends": {}}"#) -> GateResponse {
        let rules = triggeredRules.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",")
        let sugg = suggestions.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",")
        return decode("""
        {"averages": \(averages),
         "daily": [], "recommendation": "\(recommendation)",
         "tracked_days": 6, "total_days": 7, "min_tracked_days": 5,
         "triggered_rules": [\(rules)], "suggestions": [\(sugg)]}
        """)
    }

    private func morning(verdict: String? = "GO — Full Upper", carbs3d: Double? = 150, floor: Double = 120) -> MorningResponse {
        let v = verdict.map { "\"\($0)\"" } ?? "null"
        let c = carbs3d.map { "\($0)" } ?? "null"
        return decode("""
        {"today_activities": [], "verdict": \(v), "verdict_date": "2026-08-30",
         "experiment": null, "carbs_3d_avg": \(c), "carb_watch_floor": \(floor), "hrv_series": []}
        """)
    }

    // MARK: - safety / cap tier

    @Test func gateReduceDerivesAnImperativeActionWhenNoSuggestionExists() {
        let g = gate(recommendation: "REDUCE",
                     triggeredRules: ["avg_protein_7d 118.0 vs threshold 130.0 (REDUCE: insufficient protein)"])
        let s = InsightSentence.build(gate: g, morning: morning())
        #expect(s.contains("REDUCE"))
        #expect(s.contains("insufficient protein"))
        #expect(s.contains("front-load protein"))
    }

    @Test func gateReducePrefersARealSuggestionOverTheDerivedAction() {
        let g = gate(recommendation: "REDUCE",
                     triggeredRules: ["acwr 1.4 vs threshold 1.3 (REDUCE: overreaching)"],
                     suggestions: ["Take an extra rest day this week"])
        let s = InsightSentence.build(gate: g, morning: morning())
        #expect(s.contains("REDUCE"))
        #expect(s.contains("overreaching"))
        #expect(s.lowercased().contains("take an extra rest day this week"))
    }

    @Test func gateReduceWithNoParseableRuleStillProducesANonEmptyImperativeSentence() {
        let s = InsightSentence.build(gate: gate(recommendation: "REDUCE"), morning: morning())
        #expect(s.contains("REDUCE"))
        #expect(s.contains(InsightSentence.defaultAction))
    }

    /// E15-5 acceptance case, verbatim: a REDUCED fixture always carries an imperative action.
    @Test func reducedMorningVerdictSentenceContainsAnImperativeAction() {
        let s = InsightSentence.build(gate: gate(), morning: morning(verdict: "REDUCED — deload dose, not a day off"))
        #expect(s.contains("REDUCED"))
        #expect(s.contains("keep loads light") || s.contains("skip progression") || s.contains("eat at maintenance"))
        #expect(s.contains("deload dose, not a day off"))
    }

    @Test func modifiedMorningVerdictSurfacesTheSwapAsTheConcreteAction() {
        let s = InsightSentence.build(gate: gate(), morning: morning(verdict: "MODIFIED — swap intervals for easy Z2 30-40min"))
        #expect(s.contains("MODIFIED"))
        #expect(s.contains("swap intervals for easy Z2 30-40min"))
    }

    /// DEFECT NOTE (found here, pre-existing, NOT this lane's file): `MorningResponse.carbs3dAvg`
    /// never decodes from the hub. `JSON.decoder` uses `.convertFromSnakeCase`, which turns the
    /// wire key `carbs_3d_avg` into `carbs3DAvg` (capital D) — no property matches, so the value is
    /// silently nil. The same bite hits `GateAverages.avgKcal7d` / `avgProtein7d` / `sleepScore7d`
    /// (`avg_kcal_7d` -> `avgKcal7D`), which is why the gate-rationale contributors render empty.
    /// The branch itself is therefore asserted on the pure helper; the DTO fix belongs to whoever
    /// owns `JICore/DTOs/{Morning,Gate}.swift`.
    @Test func glycogenWatchFiresWhenTheCarbFloorIsBreached() {
        let s = InsightSentence.carbWatch(carbs3dAvg: 100, floor: 120)
        #expect(s?.lowercased().contains("glycogen watch") == true)
        #expect(s?.contains("front-load reflux-safe carbs") == true)
        #expect(s?.contains("100g") == true)
        #expect(s?.contains("120g") == true)
        #expect(InsightSentence.carbWatch(carbs3dAvg: 150, floor: 120) == nil)
        #expect(InsightSentence.carbWatch(carbs3dAvg: nil, floor: 120) == nil)
    }

    @Test func safetyTierOutranksTheBiggestLeverTier() {
        let g = gate(recommendation: "REDUCE",
                     triggeredRules: ["sleep_score_7d 50.0 vs threshold 55.0 (REDUCE: poor sleep)"],
                     averages: #"{"avg_protein_7d": 80, "avg_weight_kg": 80, "trends": {}}"#)
        let s = InsightSentence.build(gate: g, morning: morning())
        #expect(s.contains("REDUCE"))
        #expect(!s.contains("Protein is running"))
    }

    // MARK: - biggest-lever tier

    @Test func progressWithASuggestionSurfacesTheGatesOwnLever() {
        let g = gate(recommendation: "PROGRESS", suggestions: ["Consider increasing bench press by 2.5 kg"])
        let s = InsightSentence.build(gate: g, morning: morning())
        #expect(s.contains("increasing bench press by 2.5 kg"))
    }

    @Test func proteinGapVsTheTwoGramsPerKgGoalIsSurfacedWhenMeaningful() {
        // goal = 80 * 2.0 = 160 g, gap = 40 g >= the 10 g noise floor
        // Pure helper, for the same decoding reason as `glycogenWatchFires...` above.
        let s = InsightSentence.proteinGap(avgProtein7d: 120, avgWeightKg: 80)
        #expect(s?.contains("Protein is running 40g under your 160g target") == true)
        #expect(InsightSentence.proteinGap(avgProtein7d: 155, avgWeightKg: 80) == nil)   // 5 g gap = noise
        #expect(InsightSentence.proteinGap(avgProtein7d: 120, avgWeightKg: 0) == nil)
    }

    @Test func aSmallProteinGapIsNoiseAndFallsThroughToTheWeightTrend() {
        let g = gate(averages: #"{"avg_protein_7d": 155, "avg_weight_kg": 80, "est_weekly_weight_change_kg": -0.6, "trends": {}}"#)
        let s = InsightSentence.build(gate: g, morning: morning())
        #expect(!s.contains("Protein is running"))
        #expect(s.contains("Weight is trending down about 0.60 kg/week"))   // `est_weekly_weight_change_kg` has no digit segment, so it DOES decode
    }

    @Test func weightTrendingUpIsDescribedAsSuch() {
        let g = gate(averages: #"{"est_weekly_weight_change_kg": 0.3, "trends": {}}"#)
        let s = InsightSentence.build(gate: g, morning: morning())
        #expect(s.contains("Weight is trending up about 0.30 kg/week"))
    }

    @Test func aFlatWeightTrendIsNotALever() {
        let g = gate(averages: #"{"est_weekly_weight_change_kg": 0.01, "trends": {}}"#)
        let s = InsightSentence.build(gate: g, morning: morning())
        #expect(!s.contains("Weight is trending"))
    }

    // MARK: - fallback tier

    @Test func neverEmptyAFlatGatePlusAPlainGoVerdictStillSummarisesTheVerdict() {
        let s = InsightSentence.build(gate: gate(), morning: morning(verdict: "GO — Full Upper", carbs3d: nil))
        #expect(!s.isEmpty)
        #expect(s.contains("GO"))
        #expect(s.contains("Full Upper"))
    }

    @Test func noVerdictYetStillReturnsANonEmptySentence() {
        let s = InsightSentence.build(gate: gate(), morning: morning(verdict: nil, carbs3d: nil))
        #expect(s.lowercased().contains("no verdict yet"))
    }

    /// Swift-only: Today renders before the first fetch lands, where RN never called `buildInsight`.
    @Test func missingSectionsFallBackToTheNoVerdictCopyRatherThanAnEmptyLine() {
        #expect(InsightSentence.build(gate: nil, morning: nil) == InsightSentence.noVerdictCopy)
        #expect(InsightSentence.build(gate: gate(), morning: nil) == InsightSentence.noVerdictCopy)
    }

    // MARK: - rule parsing

    @Test func triggeredRuleParsingSplitsTheMetricAndStripsTheRecommendationPrefix() {
        let parsed = InsightSentence.parseTriggeredRule("avg_kcal_7d 1800.0 vs threshold 2000.0 (REDUCE: under-fueling)")
        #expect(parsed.metric == "avg_kcal_7d")
        #expect(parsed.reason == "under-fueling")
        let none = InsightSentence.parseTriggeredRule("acwr 1.4 vs threshold 1.3")
        #expect(none.metric == "acwr")
        #expect(none.reason == nil)
    }
}

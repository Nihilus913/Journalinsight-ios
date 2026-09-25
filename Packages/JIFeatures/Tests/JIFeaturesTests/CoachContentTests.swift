import Testing
import Foundation
import JICore
@testable import JIFeatures

/// B-57 §2/§6 Coach — pure content: ≤3 signals (newest vs 7-day mean) + one change line.
@Suite struct CoachContentTests {
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

    private func morning(verdict: String? = "GO — Full Upper", hrvSeries: String = "[]") -> MorningResponse {
        let v = verdict.map { "\"\($0)\"" } ?? "null"
        return decode("""
        {"today_activities": [], "verdict": \(v), "verdict_date": "2026-08-30",
         "experiment": null, "carbs_3d_avg": 150, "carb_watch_floor": 120, "hrv_series": \(hrvSeries)}
        """)
    }

    @Test func signalsUseNewestVsSevenDayMean() {
        let rec = (0..<7).map { i in RecoveryDay(date: "2026-09-\(15 + i)", sleepScore: [80,80,80,80,80,80,74][i], sleepDurationSec: nil, rhrBpm: [53,53,53,53,53,53,55][i], bodyBatteryAvg: nil, readinessScore: nil, acwr: nil, hrvWeeklyAvg: nil) }
        let c = CoachContentBuilder.build(morning: morning(), gate: gate(), recovery: rec, locale: Locale(identifier: "en_US"))
        #expect(c.signals.first == "Sleep 74 vs 80 avg")
        #expect(c.signals.contains("RHR 55 vs 53 avg"))
        #expect(c.signals.count <= 3)
    }
    /// W-FIX1 BUG-06: HRV is the nights' own RMSSD off `recovery`; the morning series (the 7-day
    /// `hrv_weekly_avg` mix, 60 here) is never read.
    @Test func hrvSignalFromNightlyRmssdAndCapOfThree() {
        let series = #"[{"date":"2026-09-19","hrv_weekly_avg":60},{"date":"2026-09-20","hrv_weekly_avg":60},{"date":"2026-09-21","hrv_weekly_avg":60}]"#
        let rec = (0..<3).map { i in RecoveryDay(date: "2026-09-\(19 + i)", sleepScore: [80,80,74][i], rhrBpm: [53,53,55][i], acwr: [1.0,1.0,1.11][i], hrvRmssdMs: [50,50,47][i]) }
        let c = CoachContentBuilder.build(morning: morning(hrvSeries: series), gate: gate(), recovery: rec, locale: Locale(identifier: "en_US"))
        #expect(c.signals == ["Sleep 74 vs 80 avg", "HRV 47 ms vs 50 avg", "RHR 55 vs 53 avg"])   // Load dropped: already 3
    }
    @Test func loadFillsInWhenFewerThanThree() {
        let rec = (0..<3).map { i in RecoveryDay(date: "2026-09-\(19 + i)", acwr: [1.0,1.0,1.11][i]) }
        let c = CoachContentBuilder.build(morning: morning(), gate: gate(), recovery: rec, locale: Locale(identifier: "en_US"))
        #expect(c.signals == ["Load 1.11 (last month 1.0)"])
    }
    @Test func changePrefersHubSuggestion() {
        let c = CoachContentBuilder.build(morning: morning(), gate: gate(suggestions: ["Hold the current intake for another week."]), recovery: [])
        #expect(c.change == "Hold the current intake for another week.")
    }
    @Test func changeDerivesFromTriggeredRule() {
        let c = CoachContentBuilder.build(morning: morning(), gate: gate(recommendation: "REDUCE", triggeredRules: ["acwr 1.4 vs threshold 1.3 (ACWR_HIGH: load spike)"]), recovery: [])
        #expect(c.change.hasSuffix("."))
        #expect(c.change != "Train as planned: Full Upper.")
    }
    @Test func changeFallsBackToPlannedSession() {
        let c = CoachContentBuilder.build(morning: morning(), gate: gate(), recovery: [])
        #expect(c.change == "Train as planned: Full Upper.")
    }
    @Test func coachRestDay() {
        let c = CoachContentBuilder.build(morning: morning(verdict: "REST"), gate: gate(), recovery: [])
        #expect(c.change == "Rest today — mobility and a walk.")
    }
    @Test func noSignalsWhenNoData() {
        let c = CoachContentBuilder.build(morning: nil, gate: nil, recovery: [])
        #expect(c.signals.isEmpty && c.change == "Train as planned.")
    }
}

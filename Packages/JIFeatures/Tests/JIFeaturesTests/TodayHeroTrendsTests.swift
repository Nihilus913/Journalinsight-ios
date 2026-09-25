import Testing
import Foundation
import SwiftUI
@testable import JIFeatures
import JICore
import JIDesign

/// B-42 (W-B46 L2) — the Today hero's insight lead, the ring rules and the Trends card's compute.
@Suite struct TodayHeroTrendsTests {

    // MARK: - insightLine: the verdict word is said once, and tinted

    @Test func aPlainSentenceKeepsTheVerdictWordAsItsLead() {
        let line = insightLine(word: "GO", sentence: "On track for PROGRESS — hold the current intake.")
        #expect(line.lead == "GO")
        #expect(line.rest == " — On track for PROGRESS — hold the current intake.")
    }

    @Test func theSentencesOwnVerdictOpeningIsStrippedSoTheWordIsNeverSaidTwice() {
        let colon = insightLine(word: "GO", sentence: "Verdict: GO — Full Upper.")
        #expect(colon.lead == "GO")
        #expect(colon.rest == " — Full Upper.")
        #expect(!colon.rest.contains("Verdict"))

        let isForm = insightLine(word: "REDUCED", sentence: "Verdict is REDUCED (deload dose) — keep loads light.")
        #expect(isForm.lead == "REDUCED")
        #expect(isForm.rest == " (deload dose) — keep loads light.")   // a parenthetical joins without the dash
    }

    @Test func anEmptySentenceLeavesTheLeadStandingAlone() {
        let line = insightLine(word: "—", sentence: "")
        #expect(line.lead == "—")
        #expect(line.rest.isEmpty)
    }

    @Test func aHeroRingSpeaksItsValueOrSaysThereIsNone() {
        #expect(heroRingAccessibilityLabel(label: "Readiness", value: 72) == "Readiness 72")
        #expect(heroRingAccessibilityLabel(label: "Load", value: 1.04, decimals: 2) == "Load 1.04")
        #expect(heroRingAccessibilityLabel(label: "Sleep", value: nil) == "Sleep, no data yet")
    }

    // MARK: - §4b: only bounded metrics get a ring

    @Test func onlyBoundedKpisGetARingBaselineRelativeOnesStayNumbers() {
        #expect(todayKpiRingMax(.sleep) == 100)
        #expect(todayKpiRingMax(.readiness) == 100)
        #expect(todayKpiRingMax(.bodyBattery) == 100)
        #expect(todayKpiRingMax(.steps) == todayStepsGoal)
        for id in [KpiMetricId.hrv, .rhr, .acwr, .weight, .kcal, .protein, .carbs, .fat] {
            #expect(todayKpiRingMax(id) == nil, "\(id.rawValue) is baseline-relative — never a ring (§4b)")
        }
    }

    @Test func ringTintsStayOutOfTheReservedVerdictSet() {
        for id in KpiMetricId.allCases {
            #expect(todayKpiRingRole(id) != .go)
            #expect(todayKpiRingRole(id) != .danger)
        }
    }

    // MARK: - trendAverage / todayTrends

    private func recovery(_ hrv: [Double?]) -> [RecoveryDay] {
        hrv.enumerated().map { i, v in
            RecoveryDay(date: String(format: "2026-09-%02d", i + 1), sleepScore: nil, sleepDurationSec: nil,
                        rhrBpm: nil, bodyBatteryAvg: nil, readinessScore: nil, acwr: nil, hrvWeeklyAvg: v)
        }
    }

    @Test func theAverageCoversTheLastNDaysOldestToNewest() {
        let points = (1...10).map { (date: String(format: "2026-09-%02d", $0), value: Double($0) as Double?) }
        #expect(trendAverage(points, days: 3) == 9)            // 8, 9, 10
        #expect(trendAverage(points, days: 10) == 5.5)
        #expect(trendAverage(points, days: 28) == 5.5)         // a shorter series than the window is fine
    }

    @Test func theAverageIgnoresOrderOfTheInputAndSkipsNullDaysInsteadOfCountingThemAsZero() {
        let shuffled: [(date: String, value: Double?)] = [("2026-09-03", 30), ("2026-09-01", 10), ("2026-09-02", nil)]
        #expect(trendAverage(shuffled, days: 2) == 30)          // the 2nd and 3rd day, one of them null
        #expect(trendAverage(shuffled, days: 3) == 20)          // (10 + 30) / 2, never / 3
    }

    @Test func anEmptyOrAllNullWindowHasNoAverageRatherThanZero() {
        #expect(trendAverage([], days: 7) == nil)
        #expect(trendAverage([(date: "2026-09-01", value: nil)], days: 7) == nil)
    }

    @Test func theCardShowsTheSixKpisAndComputesSevenAgainstTwentyEight() {
        // 21 days at 40 then 7 days at 60: recent = 60, baseline = (21*40 + 7*60) / 28 = 45.
        let series: [Double?] = Array(repeating: 40, count: 21) + Array(repeating: 60, count: 7)
        let trends = todayTrends(recovery: recovery(series), daily: [])
        #expect(trends.map(\.id) == ["hrv", "rhr", "sleep", "steps", "load", "weight"])
        let hrv = trends.first { $0.id == "hrv" }!
        #expect(hrv.recent == 60)
        #expect(hrv.baseline == 45)
        #expect(hrv.direction == .up)
        // Nothing but HRV is populated in this fixture — those rows report no trend, not zero.
        #expect(trends.first { $0.id == "rhr" }?.recent == nil)
        #expect(trends.first { $0.id == "rhr" }?.direction == .unknown)
    }

    @Test func stepsAndWeightComeOffTheGatesDailyRows() throws {
        let daily = try (1...8).map { d in
            try JSON.decoder.decode(DailyKpiRow.self, from: Data("""
            {"date": "2026-09-0\(d)", "steps": \(d * 1000), "weight_kg": \(100 - Double(d) * 0.1)}
            """.utf8))
        }
        let trends = todayTrends(recovery: [], daily: daily)
        let steps = trends.first { $0.id == "steps" }!
        #expect(steps.recent == 5000)                 // days 2…8
        #expect(steps.baseline == 4500)               // days 1…8
        #expect(steps.direction == .up)
        #expect(trends.first { $0.id == "weight" }?.decimals == 1)
    }

    // MARK: - render smoke

    @Test @MainActor func theHeroAndTheTrendsCardRender() {
        _ = VerdictHeroView(verdict: verdictParts("GO — Full Upper"), readiness: 72, readinessMissing: false,
                            sleepScore: 81, load: 1.04, insight: "Verdict: GO — Full Upper.").body
        _ = VerdictHeroView(verdict: verdictParts(nil), readiness: nil, readinessMissing: true,
                            sleepScore: nil, load: nil, insight: InsightSentence.noVerdictCopy).body
        // B-57 W1: the Trends card became the full Trends screen (TrendsView).
        _ = TrendsView(recovery: recovery([48, 50, 52]), daily: [], averages: nil).body
        _ = TrendsNativePreview().body
    }

    @Test func theRegistryCarriesTheTrendsEntry() {
        // B-57 W1 (L1 Task 7): "Trends card" became the full "Trends" screen.
        #expect(ScreenRegistry.entries.contains { $0.name == "Trends" })
    }
}

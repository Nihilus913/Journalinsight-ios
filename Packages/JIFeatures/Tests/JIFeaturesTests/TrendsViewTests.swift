import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

struct TrendsViewTests {
    @Test func tenCardsInBoardOrderAcrossThreeGroups() {
        let cards = trendsCards(recovery: [], daily: [], averages: nil)
        #expect(cards.map(\.id) == ["hrv", "rhr", "sleep", "load", "kcal", "protein", "carbs", "fat", "weight", "steps"])
        #expect(trendsCards(cards, filter: .nutrition).map(\.id) == ["kcal", "protein", "carbs", "fat"])
        #expect(trendsCards(cards, filter: .body).map(\.id) == ["weight", "steps"])
        #expect(trendsCards(cards, filter: .all).count == 10)
    }

    @Test func trendsCardsAllMissing() {
        for c in trendsCards(recovery: [], daily: [], averages: nil) {
            #expect(c.value == nil)
            #expect(c.status == .missing(.noData))
        }
    }

    @Test func aValueWithoutANormalSaysCalibrating() {
        let rec = (1...7).map { RecoveryDay(date: String(format: "2026-09-%02d", $0), sleepScore: nil, sleepDurationSec: 25_200,
                                            rhrBpm: 54, bodyBatteryAvg: nil, readinessScore: nil, acwr: nil, hrvWeeklyAvg: 50) }
        let cards = trendsCards(recovery: rec, daily: [], averages: nil)
        let rhr = cards.first { $0.id == "rhr" }!
        #expect(rhr.value == 54)
        #expect(rhr.status == .missing(.calibrating))
        // W-FIX1 BUG-06: `hrv_weekly_avg` is a 7-day mix, never shown as HRV.
        #expect(cards.first { $0.id == "hrv" }?.value == nil)
        let sleep = cards.first { $0.id == "sleep" }!
        #expect(sleep.value == 7)              // hours, from sleepDurationSec
        #expect(sleep.unit == "h")
    }

    /// W-FIX1 BUG-04: the hub's `avg_*_7d` follow its `window_days` (28 here), so Trends never
    /// reads them; with no daily rows the macros are "— No data".
    @Test func nutritionNeverReadsTheHubWindowAverages() {
        let avg = try! JSON.decoder.decode(GateAverages.self, from: Data(#"{"avg_kcal_7d":1619,"avg_protein_7d":127,"trends":{}}"#.utf8))
        let cards = trendsCards(recovery: [], daily: [], averages: avg)
        #expect(cards.first { $0.id == "kcal" }?.value == nil)
        #expect(cards.first { $0.id == "protein" }?.value == nil)
        #expect(cards.first { $0.id == "carbs" }?.status == .missing(.noData))
    }
}

extension TrendsViewTests {
    /// Spec §2 W1: Trends has an Edit action — hidden cards drop out, editing shows all to restore.
    @Test func editHidesAndRestoresCards() {
        let cards = trendsCards(recovery: [], daily: [], averages: nil)
        let raw = trendsToggleHidden("", id: "steps")
        #expect(raw == "steps")
        #expect(!trendsShownCards(cards, hiddenRaw: raw, editing: false).map(\.id).contains("steps"))
        #expect(trendsShownCards(cards, hiddenRaw: raw, editing: true).count == cards.count)
        #expect(trendsToggleHidden(raw, id: "steps") == "")
    }
}

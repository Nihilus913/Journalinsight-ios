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
        let hrv = cards.first { $0.id == "hrv" }!
        #expect(hrv.value == 50)
        #expect(hrv.status == .missing(.calibrating))
        let sleep = cards.first { $0.id == "sleep" }!
        #expect(sleep.value == 7)              // hours, from sleepDurationSec
        #expect(sleep.unit == "h")
    }

    @Test func nutritionReadsTheGateSevenDayAveragesOnly() {
        let avg = try! JSON.decoder.decode(GateAverages.self, from: Data(#"{"avg_kcal_7d":1619,"avg_protein_7d":127,"trends":{}}"#.utf8))
        let cards = trendsCards(recovery: [], daily: [], averages: avg)
        #expect(cards.first { $0.id == "kcal" }?.value == 1619)
        #expect(cards.first { $0.id == "protein" }?.value == 127)
        #expect(cards.first { $0.id == "carbs" }?.status == .missing(.noData))   // W2 reads dietary carbs from Health
    }
}

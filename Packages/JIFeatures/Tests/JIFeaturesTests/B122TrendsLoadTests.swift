import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

/// W-FIX-P1 RG-07 (B-122): one ACWR per day on every screen. The hub's /vitals/recovery now serves
/// today's row with the gate's last-complete-day ACWR + `acwr_as_of`; the Trends "Load" card shows
/// that ratio (not a 7-day mean of ratios — 0.89 next to Decide's 1.84) with "as of <date>".
@Suite struct B122TrendsLoadTests {
    /// /vitals/recovery 2026-10-05 from the lane hub (HT fixp1-l3), newest first.
    private static let json = """
    [{"date":"2026-10-05","acwr":1.84,"acwr_as_of":"2026-10-04"},
     {"date":"2026-10-04","acwr":1.84,"acwr_as_of":"2026-10-04"},
     {"date":"2026-10-03","acwr":1.62,"acwr_as_of":"2026-10-03"},
     {"date":"2026-10-02","acwr":0.71,"acwr_as_of":"2026-10-02"}]
    """
    private static let gateLoad = 1.84   // /planning/morning gate_signals load, as_of 2026-10-04

    private func days() throws -> [RecoveryDay] {
        try JSON.decoder.decode([RecoveryDay].self, from: Data(Self.json.utf8))
    }

    @Test func decodesAcwrAsOf() throws {
        #expect(try days().first?.acwrAsOf == "2026-10-04")
    }

    @Test func trendsLoadIsTheGatesNumberWithItsDate() throws {
        let card = try #require(trendsCards(recovery: try days(), daily: [], averages: nil, today: "2026-10-05").first { $0.id == "load" })
        #expect(card.value == Self.gateLoad)
        #expect(card.asOf == kpiAsOfLabel(valueDate: "2026-10-04", today: "2026-10-05"))
        #expect(card.asOf != nil)
        #expect(card.status.word == "Overreaching")
    }

    @Test func aCompleteTodayHasNoAsOfLabel() throws {
        let d = [RecoveryDay(date: "2026-10-05", acwr: 1.2)]
        let card = try #require(trendsCards(recovery: d, daily: [], averages: nil, today: "2026-10-05").first { $0.id == "load" })
        #expect(card.value == 1.2)
        #expect(card.asOf == nil)
    }
}

import Testing
import JICore
import JIDesign
@testable import JIFeatures

struct RecoveryTilesTests {
    private func day(_ d: Int, hrv: Double?, rhr: Double? = nil, sleepSec: Double? = nil, acwr: Double? = nil) -> RecoveryDay {
        RecoveryDay(date: String(format: "2026-09-%02d", d), sleepScore: nil, sleepDurationSec: sleepSec, rhrBpm: rhr,
                    bodyBatteryAvg: nil, readinessScore: nil, acwr: acwr, hrvWeeklyAvg: hrv)
    }

    @Test func layoutReconcilesUnknownAndMissingIds() {
        let l = recoveryTileLayout(orderRaw: "load,bogus,hrv", hiddenRaw: "rhr")
        #expect(l.visible == ["load", "hrv", "sleep"])
        #expect(l.hidden == ["rhr"])
        #expect(recoveryTileLayout(orderRaw: "", hiddenRaw: "").visible == recoveryTileIds)
    }

    @Test func recoveryTilesAllMissing() {
        let items = recoveryTileItems(days: [], layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false)
        #expect(items.map(\.id) == ["hrv", "sleep", "rhr", "load"])
        for i in items { #expect(i.value == nil); #expect(i.status == .missing(.noData)) }
    }

    @Test func tilesTakeTheNewestNonNilValue() {
        let days = [day(22, hrv: 30, rhr: 55, sleepSec: 27_000, acwr: 1.1), day(23, hrv: 25, rhr: nil, sleepSec: 26_640)]
        let items = recoveryTileItems(days: days, layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false)
        #expect(items.first { $0.id == "hrv" }?.value == 25)
        #expect(items.first { $0.id == "sleep" }?.value == 7.4)
        #expect(items.first { $0.id == "rhr" }?.value == 55)      // newest NON-nil
        #expect(items.first { $0.id == "hrv" }?.status == nil)     // a real value carries no word until W3
    }

    @Test func editingShowsHideBadgesOnlyThen() {
        let l = recoveryTileLayout(orderRaw: "", hiddenRaw: "")
        #expect(recoveryTileItems(days: [], layout: l, editing: true).allSatisfy { $0.badge == .hide })
        #expect(recoveryTileItems(days: [], layout: l, editing: false).allSatisfy { $0.badge == .none })
    }

    @Test func hrvChartIsTheLastSevenNightsNewestLast() {
        let days = (10...20).map { day($0, hrv: Double($0)) }
        let pts = recoveryHrvNights(days: days)
        #expect(pts.count == 7)
        #expect(pts.last?.isLatest == true)
        #expect(pts.last?.value == 20)
        #expect(recoveryNightLabel("2026-09-24") == "Thu")
    }
}

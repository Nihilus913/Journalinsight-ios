import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-B91 S3 (b91p3): KPI detail, the Trends "Load" tile and the Recovery "Load" tile carry the named
// ACWR status next to the ratio (the words Decide's Load row reads), never the bare number.
// Bands = hub app/vitals/load_status.py: < 0.80 Maintaining · 0.80–1.30 Productive · > 1.30 Overreaching.
@Suite struct B91LoadStatusSurfacesTests {
    private static let now = ISO8601DateFormatter().date(from: "2026-10-05T07:00:00Z")!
    private static let days = [RecoveryDay(date: "2026-10-05", acwr: 1.84)]
    private static let layout = recoveryTileLayout(orderRaw: "", hiddenRaw: "")

    private func loadSignal(_ status: String?) -> GateSignal {
        var s = GateSignal(key: "load", label: "Load", value: 1.84, unit: "", threshold: nil, direction: .max, status: .context, note: nil)
        s.loadStatus = status
        return s
    }

    @Test func bandEdgesMatchTheHub() {
        #expect(acwrNamedStatus(0.79, paused: false) == .maintaining)
        #expect(acwrNamedStatus(0.80, paused: false) == .productive)
        #expect(acwrNamedStatus(1.30, paused: false) == .productive)
        #expect(acwrNamedStatus(1.31, paused: false) == .overreaching)
        #expect(acwrNamedStatus(nil, paused: false) == nil)
        #expect(acwrNamedStatus(1.84, paused: true) == .paused)
        #expect(acwrNamedStatus(nil, paused: true) == .paused)
        #expect(acwrStatusText(1.84, paused: false) == "1.84 · Overreaching")
        #expect(acwrStatusText(1.84, paused: true) == "1.84 · Paused")
        #expect(acwrStatusText(nil, paused: true) == "Paused")
    }

    @Test func pausedComesOnlyFromTheHubLoadRow() {
        #expect(morningLoadPaused(.onDevice(verdict: nil, verdictDate: nil, carbWatchFloor: 0, isStale: nil, gateSignals: [loadSignal("paused")])))
        #expect(!morningLoadPaused(.onDevice(verdict: nil, verdictDate: nil, carbWatchFloor: 0, isStale: nil, gateSignals: [loadSignal("overreaching")])))
        #expect(!morningLoadPaused(nil))
    }

    @Test func recoveryLoadTileCarriesTheWord() throws {
        let tile = try #require(recoveryTileItems(days: Self.days, layout: Self.layout, editing: false, now: Self.now).first { $0.id == "load" })
        #expect(tile.value == 1.84)
        #expect(tile.status == .overreaching)
        #expect(recoveryLoadTileCaption(tile) == "Overreaching")
        let paused = try #require(recoveryTileItems(days: Self.days, layout: Self.layout, editing: false, now: Self.now, loadPaused: true).first { $0.id == "load" })
        #expect(paused.status == .paused)
        #expect(recoveryLoadTileCaption(paused) == "Paused")
        // The other squares keep their W1 rule (no word on a real value).
        let hrv = try #require(recoveryTileItems(days: Self.days, layout: Self.layout, editing: false, now: Self.now).first { $0.id == "hrv" })
        #expect(hrv.status == .missing(.noData))
    }

    @Test func trendsLoadTileCarriesTheWord() throws {
        let card = try #require(trendsCards(recovery: Self.days, daily: [], averages: nil, today: "2026-10-05").first { $0.id == "load" })
        #expect(card.value == 1.84)
        #expect(card.status.word == "Overreaching")
        let paused = try #require(trendsCards(recovery: Self.days, daily: [], averages: nil, today: "2026-10-05", loadPaused: true).first { $0.id == "load" })
        #expect(paused.status == .paused)
        // Today's trend row ("Load (ACWR)") too.
        let trend = try #require(todayTrends(recovery: Self.days, daily: []).first { $0.id == "load" })
        #expect(trend.status == .overreaching)
        #expect(todayTrends(recovery: Self.days, daily: [], loadPaused: true).first { $0.id == "load" }?.status == .paused)
        #expect(todayTrends(recovery: Self.days, daily: []).first { $0.id == "hrv" }?.status == nil)
    }

    @Test func kpiDetailHeroCarriesTheWord() {
        let base = kpiDetailStatus(history: [("2026-10-05", 1.84)], value: 1.84, unit: "", decimals: 2)
        let s = kpiDetailLoadStatus(metric: .acwr, value: 1.84, showsLoadMinutes: false, paused: false, base: base)
        #expect(s.word == "Overreaching")
        #expect(s.role == .reduced)
        #expect(kpiDetailLoadStatus(metric: .acwr, value: 1.84, showsLoadMinutes: false, paused: true, base: base).word == "Paused")
        // A minutes Load and other metrics keep their own status.
        #expect(kpiDetailLoadStatus(metric: .acwr, value: 300, showsLoadMinutes: true, paused: false, base: base) == base)
        #expect(kpiDetailLoadStatus(metric: .hrv, value: 1.84, showsLoadMinutes: false, paused: false, base: base) == base)
        // A too-old ratio stays "Old reading".
        let old = kpiDetailStatus(history: [("2026-09-01", 1.84)], value: 1.84, unit: "", decimals: 2, valueDate: "2026-09-01", today: "2026-10-05")
        #expect(kpiDetailLoadStatus(metric: .acwr, value: 1.84, showsLoadMinutes: false, paused: false, base: old) == old)
    }

    @Test func neverOvertraining() {
        for s in [JISignalStatus.maintaining, .productive, .overreaching, .paused] { #expect(!s.word.contains("Overtraining")) }
    }
}

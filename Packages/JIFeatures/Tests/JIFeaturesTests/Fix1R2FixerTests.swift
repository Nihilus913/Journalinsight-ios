import Foundation
import Testing
import JICore
import JIPersistence
import JIDesign
@testable import JIFeatures

/// W-FIX1 fixer (verifier r1 failures): BUG-06 (nightly RMSSD), BUG-12 (stale Load), BUG-03
/// residue (Coach overlay + Adjust sheet on the amber day). Written before the fix.

private func decode<T: Decodable>(_ json: String, as type: T.Type) -> T {
    try! JSON.decoder.decode(T.self, from: Data(json.utf8))
}

/// 2026-09-25 09:00 UTC — the regression run's morning.
private let r2Now = Date(timeIntervalSince1970: 1_790_326_800)

/// The live `/vitals/recovery` nights once the hub serves `hrv_rmssd_ms` (core.daily_vitals dso 4,
/// 09-19…09-25: 21.66 / 26.2 / 26.47 / 25 / 24.78 / 20.71 / 20.68), next to the 7-day mix.
private let r2RecoveryJSON = """
{"days":[
 {"date":"2026-09-25","hrv_weekly_avg":36,"hrv_rmssd_ms":20.68,"acwr":0.0},
 {"date":"2026-09-24","hrv_weekly_avg":28,"hrv_rmssd_ms":20.71,"acwr":0.0},
 {"date":"2026-09-23","hrv_weekly_avg":31,"hrv_rmssd_ms":24.78,"acwr":0.0},
 {"date":"2026-09-22","hrv_weekly_avg":34,"hrv_rmssd_ms":25.0,"acwr":0.0},
 {"date":"2026-09-21","hrv_weekly_avg":35,"hrv_rmssd_ms":26.47,"acwr":0.0},
 {"date":"2026-09-20","hrv_weekly_avg":36,"hrv_rmssd_ms":26.2,"acwr":0.0},
 {"date":"2026-09-19","hrv_weekly_avg":37,"hrv_rmssd_ms":21.66,"acwr":0.0},
 {"date":"2026-09-10","acwr":0.118},
 {"date":"2026-09-09","acwr":0.267}]}
"""
private var r2Recovery: [RecoveryDay] { decode(r2RecoveryJSON, as: RecoveryReport.self).days }

nonisolated private struct R2Provider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let days: [RecoveryDay]
    func health() async throws -> HealthResponse { try await MockDataProvider().health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await MockDataProvider().gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await MockDataProvider().morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await MockDataProvider().morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { days }
    func syncStatus() async throws -> SyncStatus { try await MockDataProvider().syncStatus() }
}

@MainActor private func r2Today(days: [RecoveryDay]) async throws -> TodayViewModel {
    let vm = TodayViewModel(provider: R2Provider(days: days), cache: OfflineCache(db: try AppDatabase.inMemory()),
                            prefs: PrefStore(db: try AppDatabase.inMemory()), now: { r2Now })
    await vm.load()
    return vm
}

// MARK: - BUG-06: HRV = the night's RMSSD

@Test func r2Bug06RecoveryDayDecodesTheNightlyRmssd() {
    let day = r2Recovery.first { $0.date == "2026-09-25" }
    #expect(day?.hrvRmssdMs == 20.68)
    #expect(day?.hrvWeeklyAvg == 36)
    #expect(KpiMetrics.nightlyHrvMs(day!) == 20.68)
}

@Test func r2Bug06EveryHrvSurfaceReadsTheNight() {
    // Recovery "last night" tile
    let tile = recoveryTileItems(days: r2Recovery, layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false, now: r2Now)
        .first { $0.id == "hrv" }
    #expect(tile?.value == 20.68)
    // "HRV, last 7 nights" bars: the nights, never 37/36/35/34/31/28/36
    let bars = recoveryHrvNights(days: r2Recovery).map(\.value)
    #expect(bars.suffix(7) == [21.66, 26.2, 26.47, 25.0, 24.78, 20.71, 20.68])
    // My KPIs / KPI detail headline
    #expect(KpiMetrics.latest(for: .hrv, recovery: r2Recovery, nutrition: [], dailyRows: [], gateAverages: nil)?.value == 20.68)
    // Trends: mean of the last 7 nights
    let trend = try! #require(trendsCards(recovery: r2Recovery, daily: [], averages: nil).first { $0.id == "hrv" }?.value)
    #expect(abs(trend - (21.66 + 26.2 + 26.47 + 25.0 + 24.78 + 20.71 + 20.68) / 7) < 0.001)
}

@Test @MainActor func r2Bug06DayHrvChipIsLastNight() async throws {
    let vm = try await r2Today(days: r2Recovery)
    let hrv = try #require(vm.chips.first { $0.id == "hrv" })
    #expect(hrv.value == 20.68)
    #expect(hrv.points.last == 20.68)
}

@Test func r2Bug06CoachHrvSignalIsTheNightNotTheWeeklyMix() {
    // morning.hrvSeries carries the 7-day `hrv_weekly_avg` mix (MockDataProvider: 48…52) — never read.
    let morning = decode("""
    {"today_activities":[],"verdict":null,"verdict_date":null,"carbs_3d_avg":null,"carb_watch_floor":130,
     "hrv_series":[{"date":"2026-09-24","hrv_weekly_avg":28},{"date":"2026-09-25","hrv_weekly_avg":36}]}
    """, as: MorningResponse.self)
    let c = CoachContentBuilder.build(morning: morning, gate: nil, recovery: r2Recovery, locale: Locale(identifier: "en_US"))
    let hrv = try! #require(c.signals.first { $0.hasPrefix("HRV") })
    #expect(hrv.hasPrefix("HRV 21 ms vs 24"))   // 20.68 vs mean(21.66, 26.2, 26.47, 25, 24.78, 20.71) = 24.1
    #expect(!hrv.contains("36"))
}

// MARK: - BUG-12: a 15-day-old Load is not today's load

@Test func r2Bug12StaleAcwrIsNotCurrent() {
    // newest real ACWR is 0.118 on 09-10 — 15 days before the run
    #expect(KpiMetrics.currentAcwr(r2Recovery, now: r2Now) == nil)
    let fresh = [RecoveryDay(date: "2026-09-25", acwr: 1.04)] + r2Recovery
    #expect(KpiMetrics.currentAcwr(fresh, now: r2Now) == 1.04)
    let yesterday = [RecoveryDay(date: "2026-09-24", acwr: 0.98)]
    #expect(KpiMetrics.currentAcwr(yesterday, now: r2Now) == 0.98)
}

@Test @MainActor func r2Bug12DayHeroLoadRingAndSquareAreDashWhenStale() async throws {
    let vm = try await r2Today(days: r2Recovery)
    #expect(vm.heroLoad == nil)                                    // was "0.12", undated
    #expect(vm.squareChips.first { $0.id == "acwr" }?.value == nil)
    let real = try await r2Today(days: [RecoveryDay(date: "2026-09-25", acwr: 1.08)])
    #expect(real.heroLoad == 1.08)
    #expect(real.squareChips.first { $0.id == "acwr" }?.value == 1.08)
}

@Test func r2Bug12RecoveryLoadTileIsDashWhenStale() {
    let load = recoveryTileItems(days: r2Recovery, layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false, now: r2Now)
        .first { $0.id == "load" }
    #expect(load?.value == nil)                                    // was 0.12 "as of 10 Sep"
    #expect(load?.status == .missing(.noData))
}

@Test func r2Bug12MyKpisLoadIsDashWhenStale() {
    #expect(KpiMetrics.currentReading(for: .acwr, recovery: r2Recovery, nutrition: [], dailyRows: [], gateAverages: nil, now: r2Now) == nil)
    // other metrics keep their dated reading
    let hrv = KpiMetrics.currentReading(for: .hrv, recovery: r2Recovery, nutrition: [], dailyRows: [], gateAverages: nil, now: r2Now)
    #expect(hrv?.value == 20.68)
}

// MARK: - BUG-03 residue: the amber day reads Modified everywhere

private let amber = verdictParts("GO (auto-regulated) — Day 3 Full Upper + Z2 60min")

@Test func r2Bug03CoachOverlayOnAmberDaySaysTheTrimmedSession() {
    let morning = decode("""
    {"today_activities":[],"verdict":"GO (auto-regulated) — Day 3 Full Upper + Z2 60min","verdict_date":"2026-09-25",
     "carbs_3d_avg":null,"carb_watch_floor":130,"hrv_series":[]}
    """, as: MorningResponse.self)
    let c = CoachContentBuilder.build(morning: morning, gate: nil, recovery: [])
    #expect(!c.change.hasPrefix("Train as planned"))
    #expect(c.change == "Modified: lift at current weights 1-2 reps shy of failure; trim Z2 to ~25min or walk.")
}

@Test func r2Bug03AdjustModifiedOptionMatchesTheHero() {
    let modified = try! #require(adjustChoices(parts: amber, sessionForToday: nil).first { $0.choice == .modified })
    #expect(modified.session == autoRegulatedPrescription(amber))
    #expect(modified.session.contains("trim Z2 to ~25min"))
    // Not amber: unchanged.
    let go = verdictParts("GO — Day 2 Full Upper + Z2 60min")
    #expect(localOverrideSession(choice: .modified, parts: go, sessionForToday: nil) == VerdictOverrideCopy.easySession)
}

import Foundation
import Testing
import JICore
import JIPersistence
import JIDesign
@testable import JIFeatures

/// W-FIX1 L3 "honest values" — one test per regression row (docs/audits/2026-09-25-regression-bugs.md),
/// each written from the live repro (/tmp/w-reg1/cons/*.json) before the fix.

private func decode<T: Decodable>(_ json: String, as type: T.Type) -> T {
    try! JSON.decoder.decode(T.self, from: Data(json.utf8))
}

/// 2026-09-25 09:00 UTC — the regression run's morning.
private let reg1Now = Date(timeIntervalSince1970: 1_790_326_800)
private let reg1Today = "2026-09-25"

/// The live `/vitals/recovery?window_days=28` shape on 09-25 (cons/vitals_recovery_window_days_28.json):
/// readiness 94 last seen 09-21, sleep 79 / RHR 62 last seen 09-12, body battery 90 on 09-22,
/// `acwr` 0.0 on every day, `hrv_weekly_avg` 32 on 09-24.
private let reg1Recovery: [RecoveryDay] = [
    RecoveryDay(date: "2026-09-12", sleepScore: 79, sleepDurationSec: 26_640, rhrBpm: 62, readinessScore: 70, acwr: 0, hrvWeeklyAvg: 33),
    RecoveryDay(date: "2026-09-21", bodyBatteryAvg: 31, readinessScore: 94, acwr: 0, hrvWeeklyAvg: 35),
    RecoveryDay(date: "2026-09-22", bodyBatteryAvg: 90, acwr: 0, hrvWeeklyAvg: 34),
    RecoveryDay(date: "2026-09-23", acwr: 0, hrvWeeklyAvg: 31),
    RecoveryDay(date: "2026-09-24", acwr: 0, hrvWeeklyAvg: 32),
    RecoveryDay(date: "2026-09-25", acwr: 0),
]

/// The live `/planning/gate?window_days=28` daily rows for 09-19…09-25 (cons/planning_gate_window_days_28.json),
/// with the hub's 28-day `averages` (1456 / 113 — the BUG-04 wrong "7-day" numbers).
private let reg1GateJSON = """
{"averages":{"avg_kcal_7d":1456.4,"avg_protein_7d":112.8,"avg_weight_kg":79.2,"acwr":0.0,"trends":{}},
 "daily":[
  {"date":"2026-09-25","kcal_consumed":null,"protein_g":null,"carbs_g":null,"fat_g":null,"weight_kg":79.5,"steps":null,"acwr":0.0},
  {"date":"2026-09-24","kcal_consumed":1183.1,"protein_g":98.3,"carbs_g":111.0,"fat_g":37.8,"weight_kg":79.5,"steps":9706,"acwr":0.0},
  {"date":"2026-09-23","kcal_consumed":2098.3,"protein_g":148.3,"carbs_g":150.0,"fat_g":96.5,"weight_kg":79.5,"steps":217,"acwr":0.0},
  {"date":"2026-09-22","kcal_consumed":1004.0,"protein_g":80.0,"carbs_g":90.0,"fat_g":null,"weight_kg":79.4,"steps":10337,"acwr":0.0},
  {"date":"2026-09-21","kcal_consumed":1100.0,"protein_g":95.0,"carbs_g":96.0,"fat_g":50.0,"weight_kg":79.4,"steps":13001,"acwr":0.0},
  {"date":"2026-09-20","kcal_consumed":1075.7,"protein_g":96.1,"carbs_g":79.9,"fat_g":47.0,"weight_kg":79.3,"steps":6572,"acwr":0.0},
  {"date":"2026-09-19","kcal_consumed":null,"protein_g":null,"carbs_g":null,"fat_g":null,"weight_kg":79.3,"steps":5755,"acwr":0.0}],
 "recommendation":"REDUCE","tracked_days":5,"total_days":8,"min_tracked_days":5,"triggered_rules":[],"suggestions":[]}
"""

nonisolated private struct Reg1Provider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let days: [RecoveryDay]
    func health() async throws -> HealthResponse { try await MockDataProvider().health() }
    func gate(windowDays: Int) async throws -> GateResponse { decode(reg1GateJSON, as: GateResponse.self) }
    func morning() async throws -> MorningResponse { try await MockDataProvider().morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await MockDataProvider().morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { days }
    func syncStatus() async throws -> SyncStatus { try await MockDataProvider().syncStatus() }
}

@MainActor private func reg1Today(days: [RecoveryDay] = reg1Recovery, now: Date = reg1Now) async throws -> TodayViewModel {
    let vm = TodayViewModel(provider: Reg1Provider(days: days), cache: OfflineCache(db: try AppDatabase.inMemory()),
                            prefs: PrefStore(db: try AppDatabase.inMemory()), now: { now })
    await vm.load()
    return vm
}

// MARK: - BUG-05: stale values shown as current with no date

@Test func bug05LastNightFreshnessIs36Hours() {
    // A night dated D is read that morning; older than 36 h it is no longer "last night".
    #expect(KpiMetrics.isLastNightFresh(nightDate: "2026-09-25", now: reg1Now))
    #expect(KpiMetrics.isLastNightFresh(nightDate: "2026-09-24", now: reg1Now))
    #expect(!KpiMetrics.isLastNightFresh(nightDate: "2026-09-21", now: reg1Now))
    #expect(!KpiMetrics.isLastNightFresh(nightDate: "2026-09-12", now: reg1Now))
    #expect(!KpiMetrics.isLastNightFresh(nightDate: "garbage", now: reg1Now))
}

@Test @MainActor func bug05DayReadinessFromFourDaysAgoIsNotShownAsToday() async throws {
    let vm = try await reg1Today()
    #expect(vm.readiness == nil)            // was 94 (09-21)
    let fresh = try await reg1Today(days: [RecoveryDay(date: "2026-09-25", readinessScore: 71)])
    #expect(fresh.readiness == 71)
}

@Test @MainActor func bug05DayNightChipsAreDashWhenStale() async throws {
    let vm = try await reg1Today()
    let byId = Dictionary(uniqueKeysWithValues: vm.chips.map { ($0.id, $0) })
    #expect(byId["sleep"]?.value == nil)    // was 79 (09-12) — feeds the Day hero Sleep ring
    #expect(byId["rhr"]?.value == nil)      // was 62 (09-12)
    // Yesterday's night (inside 36 h) still shows, carrying its date.
    let y = try await reg1Today(days: [RecoveryDay(date: "2026-09-24", sleepScore: 81, rhrBpm: 58)])
    let sleep = try #require(y.chips.first { $0.id == "sleep" })
    #expect(sleep.value == 81)
    #expect(sleep.asOf?.hasPrefix("as of ") == true)
}

@Test func bug05RecoveryLastNightTilesAreDashWhenStale() {
    let items = recoveryTileItems(days: reg1Recovery, layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false, now: reg1Now)
    let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    #expect(byId["sleep"]?.value == nil)    // was 7.4 h (09-12)
    #expect(byId["rhr"]?.value == nil)      // was 62 (09-12)
    #expect(byId["sleep"]?.status == .missing(.noData))
    // Yesterday's night shows with its date.
    let y = recoveryTileItems(days: [RecoveryDay(date: "2026-09-24", rhrBpm: 58)], layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""),
                              editing: false, now: reg1Now)
    let rhr = try! #require(y.first { $0.id == "rhr" })
    #expect(rhr.value == 58)
    #expect(rhr.goalText?.hasPrefix("as of ") == true)
}

@Test func bug05MyKpiSquaresCarryTheirDate() {
    let reading = KpiReading(value: 62, date: "2026-09-12")
    let items = kpiCatalogueItems(group: .recovery, visible: [], value: { $0 == .rhr ? reading : nil }, today: reg1Today)
    let rhr = try! #require(items.first { $0.id == "rhr" })
    #expect(rhr.value == 62)
    #expect(rhr.goalText?.hasPrefix("as of ") == true)
    // Today's own reading carries no date caption.
    let todayItems = kpiCatalogueItems(group: .recovery, visible: [], value: { _ in KpiReading(value: 1, date: reg1Today) }, today: reg1Today)
    #expect(todayItems.allSatisfy { $0.goalText == nil })
}

// MARK: - BUG-06: HRV is last night's value, never the 7-day mix

@Test func bug06HrvNeverReadsTheSevenDayMix() {
    // `hrv_weekly_avg` is a 7-day average mixing Garmin RMSSD with Apple SDNN — not a night.
    #expect(KpiMetrics.latest(for: .hrv, recovery: reg1Recovery, nutrition: [], dailyRows: [], gateAverages: nil) == nil)
    #expect(KpiMetrics.history(for: .hrv, recovery: reg1Recovery, nutrition: [], dailyRows: []).allSatisfy { $0.value == nil })
    let tile = recoveryTileItems(days: reg1Recovery, layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false, now: reg1Now)
        .first { $0.id == "hrv" }
    #expect(tile?.value == nil)             // was 32 "last night"
    #expect(tile?.status == .missing(.noData))
    #expect(recoveryHrvNights(days: reg1Recovery).allSatisfy { $0.value == nil })   // was 37/36/35/34/31/32
    #expect(trendsCards(recovery: reg1Recovery, daily: [], averages: nil).first { $0.id == "hrv" }?.value == nil)
}

@Test @MainActor func bug06DayHrvChipIsNotTheWeeklyAverage() async throws {
    let vm = try await reg1Today()
    let hrv = try #require(vm.chips.first { $0.id == "hrv" })
    #expect(hrv.value == nil)
    #expect(hrv.points.allSatisfy { $0 == nil })
}

// MARK: - BUG-12: Load reads "0.00" everywhere (an invented ACWR)

@Test func bug12ZeroAcwrIsNoLoadDataNotAValue() {
    #expect(KpiMetrics.honestAcwr(0) == nil)
    #expect(KpiMetrics.honestAcwr(nil) == nil)
    #expect(KpiMetrics.honestAcwr(1.04) == 1.04)
    #expect(KpiMetrics.latest(for: .acwr, recovery: reg1Recovery, nutrition: [], dailyRows: [], gateAverages: nil) == nil)
    let load = recoveryTileItems(days: reg1Recovery, layout: recoveryTileLayout(orderRaw: "", hiddenRaw: ""), editing: false, now: reg1Now)
        .first { $0.id == "load" }
    #expect(load?.value == nil)
    #expect(load?.status == .missing(.noData))
    let card = trendsCards(recovery: reg1Recovery, daily: [], averages: nil).first { $0.id == "load" }
    #expect(card?.value == nil)
    #expect(card?.status == .missing(.noData))
}

@Test @MainActor func bug12DayLoadAndEditTodaySquareAreDash() async throws {
    let vm = try await reg1Today()
    // TodayView's hero Load ring reads `recovery`'s newest non-nil `acwr` directly.
    #expect(vm.recovery.compactMap(\.acwr).isEmpty)
    #expect(vm.squareChips.first { $0.id == "acwr" }?.value == nil)
    // A real ACWR still comes through.
    let real = try await reg1Today(days: [RecoveryDay(date: "2026-09-25", acwr: 1.08)])
    #expect(real.squareChips.first { $0.id == "acwr" }?.value == 1.08)
}

// MARK: - BUG-04 (app half): Trends "7-day" values are 7-day values

@Test func bug04TrendsNutritionIsTheLastSevenDaysNotTheHubWindow() {
    let gate = decode(reg1GateJSON, as: GateResponse.self)
    let cards = Dictionary(uniqueKeysWithValues: trendsCards(recovery: [], daily: gate.daily, averages: gate.averages).map { ($0.id, $0) })
    // Mean of the 7 rows' real values: (1183.1+2098.3+1004+1100+1075.7)/5, not the hub's 28-day 1456.
    let kcal = try! #require(cards["kcal"]?.value)
    #expect(abs(kcal - 1292.22) < 0.01)
    let protein = try! #require(cards["protein"]?.value)
    #expect(abs(protein - 103.54) < 0.01)
}

// MARK: - BUG-32: Trends Carbs / Fat read "— No data" though the gate daily carries them

@Test func bug32TrendsCarbsAndFatComeFromTheDailyRows() {
    let gate = decode(reg1GateJSON, as: GateResponse.self)
    let cards = Dictionary(uniqueKeysWithValues: trendsCards(recovery: [], daily: gate.daily, averages: gate.averages).map { ($0.id, $0) })
    let carbs = try! #require(cards["carbs"]?.value)
    #expect(abs(carbs - 105.38) < 0.01)     // (111+150+90+96+79.9)/5
    let fat = try! #require(cards["fat"]?.value)
    #expect(abs(fat - 57.825) < 0.001)      // (37.8+96.5+50+47)/4
    #expect(cards["carbs"]?.status == .missing(.calibrating))
}

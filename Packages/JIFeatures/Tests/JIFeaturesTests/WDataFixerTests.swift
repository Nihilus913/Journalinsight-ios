import Foundation
import Testing
import JICore
import JICompute
import JIDesign
@testable import JIFeatures

// W-DATA fixer (verifier FAIL rows R9-app, R1-label, R3-computed).

private let today = "2026-09-27"

private func day(_ k: Int) -> String { try! CalendarMath.addDays(today, -k) }

/// 42 days of `load_min` like the live route (two days missing), 6 min so far today.
private func loadDays(missing: Set<Int> = [10, 20]) -> [RecoveryInputDay] {
    (0..<42).reversed().map { k in
        RecoveryInputDay(date: day(k), loadMin: missing.contains(k) ? nil : (k == 0 ? 6 : 30 + Double(k % 5) * 10))
    }
}

// MARK: - R9: Load from the gate's inputs, with its band

@Test func loadReadingIsTheScoresSevenDayLoadWithItsBand() throws {
    let days = loadDays()
    let r = try #require(recoveryLoadReading(days: days, today: today))
    // The same number the recovery score's load component uses.
    let series = days.map { RecoverySeriesDay(date: $0.date, loadMin: $0.loadMin) }
    let score = try RecoveryScore.compute(days: series, today: today)
    #expect(r.minutes == score.component(.load)?.value)
    let normal = try #require(r.normal)
    #expect(r.caption == "7 days · normal \(jiNumber(normal.low, 0))–\(jiNumber(normal.high, 0))")
    #expect(r.valueText == "\(jiNumber(r.minutes, 0)) min")
    #expect(r.points.count == 7 && r.points.last == 6)
}

@Test func loadReadingCalibratesWithoutEnoughWeeks() throws {
    let recent = loadDays().suffix(10)   // 10 days: a 7-day load, but no 28-value normal
    let r = try #require(recoveryLoadReading(days: Array(recent), today: today))
    #expect(r.normal == nil)
    #expect(r.caption == "7 days · Calibrating")
}

@Test func loadReadingIsNilWithoutFourDaysOfLoad() {
    let sparse = [RecoveryInputDay(date: day(1), loadMin: 30), RecoveryInputDay(date: day(2), loadMin: 30)]
    #expect(recoveryLoadReading(days: sparse, today: today) == nil)
    #expect(recoveryLoadReading(days: [], today: today) == nil)
}

@Test func todayLoadSquareTakesTheMinutesWhenAcwrIsMissing() throws {
    let load = try #require(recoveryLoadReading(days: loadDays(), today: today))
    let chips = [TodayChip(id: "hrv", label: "HRV", value: 40, unit: "ms", points: [], sourceMissing: false),
                 TodayChip(id: "acwr", label: "Load", value: nil, unit: nil, points: [], sourceMissing: false)]
    let out = todayChipsWithLoad(chips, load: load)
    #expect(out[0] == chips[0])
    #expect(out[1].value == load.minutes.rounded() && out[1].unit == "min" && out[1].asOf == load.caption)
    let spec = todaySummaryCardSpec(for: out[1])
    #expect(spec.value == jiNumber(load.minutes.rounded(), 0))   // whole minutes, never ACWR's 2 dp
    #expect(spec.unit == "min" && spec.timestamp == load.caption)
    // A real ACWR keeps the square; no load keeps everything as it was.
    let real = [TodayChip(id: "acwr", label: "Load", value: 1.04, unit: nil, points: [], sourceMissing: false)]
    #expect(todayChipsWithLoad(real, load: load) == real)
    #expect(todayChipsWithLoad(chips, load: nil) == chips)
}

// MARK: - R1: Fuel names its day

@Test func fuelHeaderNamesAnEarlierDay() {
    #expect(dayFuelTitle(asOf: nil) == "Fuel today")
    #expect(dayFuelTitle(asOf: "as of Sep 24") == "Fuel · last logged")
}

@Test func fuelLeftIsOnlyForToday() {
    #expect(dayFuelLeftText(kcal: 865, goal: 1617, isToday: true) == "752 left · your goal")
    #expect(dayFuelLeftText(kcal: 865, goal: 1617, isToday: false) == "752 under your goal")
    #expect(dayFuelLeftText(kcal: 1700, goal: 1617, isToday: false) == "83 over your goal")
}

@Test func moreNutritionFallsBackToTheLatestLoggedDay() {
    let week = [NutritionDailyRow(date: "2026-09-24", kcalConsumed: 865),
                NutritionDailyRow(date: "2026-09-25"),
                NutritionDailyRow(date: "2026-09-23", kcalConsumed: 1500)]
    let latest = moreNutritionLatestIntake(today: today, todayKcal: nil, week: week)
    #expect(latest?.kcal == 865 && latest?.date == "2026-09-24")
    #expect(moreNutritionLatestIntake(today: today, todayKcal: 400, week: week)?.date == today)
    #expect(moreNutritionLatestIntake(today: today, todayKcal: nil, week: []) == nil)
    let v = moreNutritionValue(consumedKcal: 865, goalKcal: 1617, asOf: "as of Sep 24")
    #expect(v.text == "865 / 1617 kcal · as of Sep 24")
    #expect(moreNutritionValue(consumedKcal: nil, goalKcal: 1617, asOf: nil).text == "— No data")
}

// MARK: - R3: Readiness is the recovery score Decide shows

@Test func readinessTileShowsTheRecoveryScore() {
    let ok = RecoveryScoreResult(status: .ok, score: 32, raw: -1.1, components: [], nights: 28)
    let tiles = healthComputedTiles(sleepScore: 84, readiness: ok)
    #expect(tiles[0].value == "32" && !tiles[0].note.localizedCaseInsensitiveContains("garmin"))
    #expect(tiles[1].value == "84")
    let cal = RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: [], nights: 5)
    #expect(healthComputedTiles(sleepScore: nil, readiness: cal)[0].value == "—")
    #expect(healthComputedTiles(sleepScore: nil, readiness: cal)[0].note == "Calibrating")
    let missing = RecoveryScoreResult(status: .missing, score: nil, raw: nil, components: [], nights: 28)
    #expect(healthComputedTiles(sleepScore: nil, readiness: missing)[0].note == "No data")
}

@Test @MainActor func readinessComesFromTheWiredLoader() async {
    let ok = RecoveryScoreResult(status: .ok, score: 32, raw: -1.1, components: [], nights: 28)
    let vm = HealthPermissionViewModel(permission: .granted, requestPermission: { .granted }, openHealthSettings: {},
                                       loadSleepScore: { 84 }, loadReadiness: { ok })
    await vm.refreshComputed()
    #expect(vm.sleepScore == 84 && vm.readiness == ok)
}

@Test func recoveryScoreHelperMatchesTheService() throws {
    let days = MockDataProvider.recoveryInputDays(date: "2026-09-24", windowDays: 42)
    let r = RecoveryInsightService.score(days: days, today: "2026-09-24")
    let series = days.map { RecoverySeriesDay(date: $0.date, hrvMs: $0.hrvMs, rhrBpm: $0.rhrBpm, sleepH: $0.sleepH,
                                              deepH: $0.deepH, remH: $0.remH, loadMin: $0.loadMin) }
    #expect(r == (try RecoveryScore.compute(days: series, today: "2026-09-24")))
    #expect(RecoveryInsightService.score(days: [], today: "2026-09-24") == nil)
}

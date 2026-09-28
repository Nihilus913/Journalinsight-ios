import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

/// Hub has a week row for the day but no day detail (the device state 2026-09-28: the week strip
/// named the day's kcal while the card said "No data").
private nonisolated struct NutritionWeekOnlyProvider: NutritionProviding {
    let rows: [NutritionDailyRow]
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { nil }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { rows }
}

/// W-FIX8 L2: M-1 (Macros reads Health, hub is the labelled fallback), M-2 (week strip), M-3 (More rows).
@MainActor @Suite struct Fix8NutritionMoreTests {
    static func feed(_ rows: [HealthDailyTotals]) -> HealthDailyTotalsFeed {
        let f = HealthDailyTotalsFeed(); f.publish(rows); return f
    }

    // MARK: M-1

    @Test func healthOnlyProtein118ShowsOnTheCardFromAppleHealth() async throws {
        let feed = Self.feed([HealthDailyTotals(date: "2026-09-28", dietaryKcal: 933, proteinG: 118)])
        let vm = NutritionViewModel(provider: NutritionEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                    initialDate: "2026-09-28", healthFeed: feed)
        await vm.load()
        let total = try #require(vm.day?.total)
        #expect(total.proteinG == 118)
        #expect(macroSummaryRows(total, goals: NutritionGoalsSnapshot(macros: nil)).first?.text.hasPrefix("118 g") == true)
        #expect(vm.daySource == .appleHealth)
        #expect(NutritionDataSource.appleHealth.caption == "From Apple Health")
    }

    @Test func hubOnlyDayShowsTheHubValueAndSaysSo() async throws {
        let rows = [NutritionDailyRow(date: "2026-09-28", kcalConsumed: 1183, proteinG: 90, carbsG: 120, fatG: 40, mealsLogged: 3)]
        let vm = NutritionViewModel(provider: NutritionWeekOnlyProvider(rows: rows), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                    initialDate: "2026-09-28", healthFeed: HealthDailyTotalsFeed())
        await vm.load()
        #expect(vm.day?.total.kcal == 1183 && vm.day?.total.proteinG == 90)
        #expect(vm.daySource == .hub)
        #expect(NutritionDataSource.hub.caption == "From YAZIO via the hub")
    }

    @Test func noDataAnywhereHasNoSource() async throws {
        let vm = NutritionViewModel(provider: NutritionEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                    initialDate: "2026-09-28", healthFeed: HealthDailyTotalsFeed())
        await vm.load()
        #expect(vm.day == nil && vm.daySource == nil)
    }

    /// The default day is the device's LOCAL day (Health keys are local days); UTC named
    /// yesterday between local midnight and 02:00 in Zurich.
    @Test func defaultSelectedDateIsTheLocalDay() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let vm = NutritionViewModel(provider: NutritionEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                    now: { now }, healthFeed: HealthDailyTotalsFeed())
        #expect(vm.selectedDate == energyTodayISO(now))
    }

    // MARK: M-2

    @Test func selectedDayWithAWeekRowShowsItsValuesNotNoData() async throws {
        let rows = [NutritionDailyRow(date: "2026-09-25", kcalConsumed: 1500, proteinG: 110),
                    NutritionDailyRow(date: "2026-09-26", kcalConsumed: 1700, proteinG: 120)]
        let vm = NutritionViewModel(provider: NutritionWeekOnlyProvider(rows: rows), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                    initialDate: "2026-09-28", healthFeed: HealthDailyTotalsFeed())
        await vm.load()
        await vm.selectDate("2026-09-25")
        #expect(vm.day?.total.kcal == 1500 && vm.day?.total.proteinG == 110)
    }

    @Test func stripShowsSevenDaysEndingTodayRingOnlyOnLoggedDays() {
        let week = [NutritionDailyRow(date: "2026-09-24", kcalConsumed: 1183), NutritionDailyRow(date: "2026-09-27", kcalConsumed: nil)]
        let rows = nutritionStripRows(week: week, today: "2026-09-28")
        #expect(rows.map(\.date) == ["2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28"])
        #expect(rows.filter { $0.kcalConsumed != nil }.map(\.date) == ["2026-09-24"])
        #expect(nutritionStripLegend == "Ring = food logged · filled = selected day")
    }

    // MARK: M-3

    /// More › Energy names the Energy hero's number: the phone's Health band balance when it has
    /// one (the hub report may be < 4 tracking days while Health has the week).
    @Test func moreEnergyEqualsTheHeroBalance() {
        #expect(energyBalanceDeficit(avgDeficit7d: nil, trackingDays: 1, bandBalanceKcal: -420) == 420)
        #expect(moreEnergyValue(avgDeficit7d: nil, trackingDays: 1, bandBalanceKcal: -420).text
                == "\(energyHeroNumeral(420)) 7-day avg vs TDEE")
        #expect(energyBalanceDeficit(avgDeficit7d: 598, trackingDays: 3, bandBalanceKcal: nil) == nil)   // gated
        #expect(energyBalanceDeficit(avgDeficit7d: 598, trackingDays: 7, bandBalanceKcal: nil) == 598)
        #expect(moreEnergyValue(avgDeficit7d: 598, trackingDays: 7).text == "\u{2212}598 7-day avg vs TDEE")
    }
}

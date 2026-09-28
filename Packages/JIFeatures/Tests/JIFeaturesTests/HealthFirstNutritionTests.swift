import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX7 N-1 / N-2: Fuel, Nutrition, Energy and the KPI screens read Apple Health daily totals
/// first and the hub's YAZIO rows only for days Health lacks; "—" when neither has the day.
@MainActor @Suite struct HealthFirstNutritionTests {
    static func feed(_ rows: [HealthDailyTotals]) -> HealthDailyTotalsFeed {
        let f = HealthDailyTotalsFeed(); f.publish(rows); return f
    }

    // MARK: Nutrition

    @Test func nutritionDayAndWeekTakeHealthForItsDaysAndKeepYazioMeals() async throws {
        let feed = Self.feed([HealthDailyTotals(date: "2026-09-11", dietaryKcal: 2222, proteinG: 171, carbsG: 202, fatG: 66)])
        let vm = NutritionViewModel(provider: NutritionFlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                    initialDate: "2026-09-11", healthFeed: feed)
        await vm.load()
        #expect(vm.day?.total.kcal == 2222 && vm.day?.total.proteinG == 171 && vm.day?.total.fatG == 66)
        #expect(vm.day?.items.isEmpty == false)                       // meals stay YAZIO's
        #expect(vm.week.first { $0.date == "2026-09-11" }?.kcalConsumed == 2222)
        #expect(vm.week.count <= 7)
    }

    @Test func nutritionHealthOnlyDayIsLoadedNotEmpty() async throws {
        let feed = Self.feed([HealthDailyTotals(date: "2026-09-28", dietaryKcal: 900, proteinG: 60)])
        let vm = NutritionViewModel(provider: NutritionEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()),
                                    initialDate: "2026-09-28", healthFeed: feed)
        await vm.load()
        #expect(vm.phase == .loaded)
        #expect(vm.day?.total.kcal == 900 && vm.day?.total.carbsG == nil)   // nil stays nil, never 0
        #expect(vm.week.map(\.date) == ["2026-09-28"])
    }

    @Test func nutritionFallsBackToTheBandsCachedHealthTotals() async throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        try cache.put(EnergyBandService.cacheKey, [HealthDailyTotals(date: "2026-09-28", dietaryKcal: 1234)])
        let vm = NutritionViewModel(provider: NutritionEmptyProvider(), cache: cache, initialDate: "2026-09-28", healthFeed: HealthDailyTotalsFeed())
        await vm.load()
        #expect(vm.day?.total.kcal == 1234)
    }

    // MARK: Today Fuel

    @Test func fuelTakesTodaysHealthFood() async throws {
        let feed = HealthDailyTotalsFeed()
        let vm = TodayViewModel(provider: FlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()), healthFeed: feed)
        await vm.load()
        let hubDates = (vm.gate?.daily ?? []).map(\.date)
        let newest = try #require(hubDates.max())
        let steps = vm.gate?.daily.first { $0.date == newest }?.values["steps"] ?? nil
        feed.publish([HealthDailyTotals(date: newest, dietaryKcal: 1999, proteinG: 150, carbsG: 180, fatG: 60)])
        let fuel = dayFuel(daily: vm.gate?.daily ?? [], today: newest)
        #expect(fuel.kcal == 1999 && fuel.protein == 150 && fuel.carbs == 180 && fuel.fat == 60 && fuel.asOf == nil)
        #expect((vm.gate?.daily.first { $0.date == newest }?.values["steps"] ?? nil) == steps)   // non-food keys stay the hub's
        #expect(vm.gate?.daily.count == hubDates.count)
    }

    // MARK: Energy

    @Test func energyDayIntakeComesFromHealth() async throws {
        let feed = HealthDailyTotalsFeed()
        let vm = EnergyViewModel(provider: EnergyFlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()), healthFeed: feed)
        await vm.load()
        let day = try #require(vm.days.first)
        feed.publish([HealthDailyTotals(date: day.date, dietaryKcal: 1111)])
        #expect(vm.days.first { $0.date == day.date }?.kcalConsumed == 1111)
        #expect(vm.report?.days.first { $0.date == day.date }?.kcalConsumed == 1111)
    }

    // MARK: KPI detail + catalogue

    @Test func kpiDetailMacroReadsHealthFirst() async throws {
        let feed = Self.feed([HealthDailyTotals(date: "2099-01-01", dietaryKcal: 1777, proteinG: 144)])
        let vm = KpiDetailViewModel(metric: .protein, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
                                    targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()), healthFeed: feed)
        await vm.load()
        #expect(vm.latest?.value == 144 && vm.latest?.date == "2099-01-01")
    }

    @Test func fibreAndSugarSquaresReadHealthWithTheirDay() {
        let health = [HealthDailyTotals(date: "2026-09-27", fiberG: 29.4, sugarG: 51), HealthDailyTotals(date: "2026-09-28", fiberG: 12)]
        let n = kpiCatalogueItems(group: .nutrition, visible: [], value: { _ in nil }, today: "2026-09-28",
                                  goalCaption: { _, _ in nil }, load: nil, health: health)
        let fibre = n.first { $0.id == "fibre" }
        let sugar = n.first { $0.id == "sugar" }
        #expect(fibre?.value == 12 && fibre?.status == nil && fibre?.unit == "g" && fibre?.badge == .add)
        #expect(sugar?.value == 51 && sugar?.goalText == kpiAsOfLabel(valueDate: "2026-09-27", today: "2026-09-28"))
        let none = kpiCatalogueItems(group: .nutrition, visible: [], value: { _ in nil }, today: "2026-09-28",
                                     goalCaption: { _, _ in nil }, load: nil, health: [])
        #expect(none.first { $0.id == "fibre" }?.status == .missing(.noData))
    }
}

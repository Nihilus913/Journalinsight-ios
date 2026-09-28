import Foundation
import Testing
@testable import JICore

/// W-FIX7 N-1 / N-2: Apple Health daily totals first, the hub's YAZIO rows only for days Health
/// lacks; a day neither has stays nil (never 0).
@Suite struct HealthDailyTotalsMergeTests {
    static let health: [HealthDailyTotals] = [
        HealthDailyTotals(date: "2026-09-26", activeKcal: 400),                                    // no food in Health
        HealthDailyTotals(date: "2026-09-27", dietaryKcal: 2100, proteinG: 160, carbsG: 210, fatG: 70, fiberG: 28, sugarG: 40),
        HealthDailyTotals(date: "2026-09-28", dietaryKcal: 900, proteinG: 60, carbsG: 80, fatG: 30),
    ]

    @Test func fibreAndSugarRoundTripAndCountAsValues() throws {
        let t = HealthDailyTotals(date: "2026-09-28", fiberG: 12)
        #expect(t.hasAnyValue && t.hasFood == false)
        #expect(HealthDailyTotals(date: "x", sugarG: 3).hasAnyValue)
        // An old cache entry (no fibre/sugar keys) still decodes, nil not 0.
        let old = #"[{"date":"2026-09-20","dietaryKcal":1800}]"#.data(using: .utf8)!
        let rows = try JSONDecoder().decode([HealthDailyTotals].self, from: old)
        #expect(rows[0].dietaryKcal == 1800 && rows[0].fiberG == nil && rows[0].sugarG == nil)
    }

    @Test func nutritionRowsPreferHealthPerDayAndFillHealthOnlyDays() {
        let hub = [
            NutritionDailyRow(date: "2026-09-25", kcalConsumed: 1700, kcalGoal: 2200, proteinG: 140, mealsLogged: 3),
            NutritionDailyRow(date: "2026-09-26", kcalConsumed: 1600, proteinG: 130),
            NutritionDailyRow(date: "2026-09-27", kcalConsumed: 1500, kcalGoal: 2200, proteinG: 120, carbsG: 1, fatG: 1, mealsLogged: 4),
        ]
        let merged = NutritionDailyRow.mergingHealth(hub, health: Self.health)
        #expect(merged.map(\.date) == ["2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28"])
        #expect(merged[0] == hub[0])                                   // Health lacks the day → YAZIO
        #expect(merged[1] == hub[1])                                   // Health has no food that day → YAZIO
        #expect(merged[2] == NutritionDailyRow(date: "2026-09-27", kcalConsumed: 2100, kcalGoal: 2200, proteinG: 160, carbsG: 210, fatG: 70, mealsLogged: 4))
        #expect(merged[3] == NutritionDailyRow(date: "2026-09-28", kcalConsumed: 900, proteinG: 60, carbsG: 80, fatG: 30))
    }

    @Test func nutritionMergeKeepsNewestFirstOrderAndWindowFloor() {
        let hub = [NutritionDailyRow(date: "2026-09-27", kcalConsumed: 1), NutritionDailyRow(date: "2026-09-20", kcalConsumed: 2)]
        let merged = NutritionDailyRow.mergingHealth(hub, health: Self.health)
        #expect(merged.map(\.date) == ["2026-09-28", "2026-09-27", "2026-09-20"])
        #expect(NutritionDailyRow.mergingHealth([], health: []) == [])
        #expect(NutritionDailyRow.mergingHealth([], health: Self.health).map(\.date) == ["2026-09-27", "2026-09-28"])
    }

    @Test func dayDetailTotalComesFromHealthWhenItHasTheDay() {
        let detail = NutritionDayDetail(date: "2026-09-27", total: NutritionDayTotal(kcal: 1500, kcalGoal: 2200, proteinG: 120, mealsLogged: 4),
                                        breakdown: NutritionDayBreakdown(lunch: 600), items: ["lunch": [NutritionMealItem(name: "Rice")]])
        let merged = NutritionDayDetail.mergingHealth(detail, date: "2026-09-27", health: Self.health)
        #expect(merged?.total == NutritionDayTotal(kcal: 2100, kcalGoal: 2200, proteinG: 160, carbsG: 210, fatG: 70, mealsLogged: 4))
        #expect(merged?.items == detail.items)
        // Health-only day: a total, no meals (the meal list is YAZIO's) — never a zeroed day.
        let only = NutritionDayDetail.mergingHealth(nil, date: "2026-09-28", health: Self.health)
        #expect(only?.total == NutritionDayTotal(kcal: 900, proteinG: 60, carbsG: 80, fatG: 30))
        #expect(only?.items.isEmpty == true)
        #expect(NutritionDayDetail.mergingHealth(nil, date: "2026-09-26", health: Self.health) == nil)
        #expect(NutritionDayDetail.mergingHealth(detail, date: "2026-09-26", health: Self.health) == detail)
    }

    @Test func energyDaysRecomputeTheDeficitFromHealthIntake() {
        let hub = [
            EnergyDay(date: "2026-09-27", kcalConsumed: 1500, tdeeRaw: 2500, tdeeCorrected: 2400, deficitRaw: 1000, deficitCorrected: 900,
                      deficitPctRaw: 40, deficitPctCorrected: 37.5, deficitClass: "dangerous", mealsLogged: 4),
            EnergyDay(date: "2026-09-26", kcalConsumed: 1600, tdeeRaw: 2500),
        ]
        let merged = EnergyDay.mergingHealth(hub, health: Self.health)
        #expect(merged.map(\.date) == ["2026-09-28", "2026-09-27", "2026-09-26"])
        let d27 = merged[1]
        #expect(d27.kcalConsumed == 2100 && d27.tdeeRaw == 2500 && d27.tdeeCorrected == 2400 && d27.mealsLogged == 4)
        #expect(d27.deficitRaw == 400 && d27.deficitCorrected == 300)
        #expect(d27.deficitPctRaw == 16 && d27.deficitPctCorrected == 12.5 && d27.deficitClass == "mild")
        #expect(merged[2] == hub[1])
        #expect(merged[0] == EnergyDay(date: "2026-09-28", kcalConsumed: 900))   // no TDEE → no deficit, never 0
    }

    @Test func gateRowsTakeHealthFoodAndLeaveOtherKeys() {
        let hub = [
            DailyKpiRow(date: "2026-09-27", values: ["kcal_consumed": 1500, "protein_g": 120, "steps": 9000, "fat_g": nil]),
            DailyKpiRow(date: "2026-09-26", values: ["kcal_consumed": 1600, "steps": 8000]),
        ]
        let merged = DailyKpiRow.mergingHealth(hub, health: Self.health)
        #expect(merged.map(\.date) == ["2026-09-28", "2026-09-27", "2026-09-26"])
        #expect(merged[1].values["kcal_consumed"] == 2100 && merged[1].values["protein_g"] == 160)
        #expect(merged[1].values["carbs_g"] == 210 && merged[1].values["fat_g"] == 70 && merged[1].values["steps"] == 9000)
        #expect(merged[2] == hub[1])
        #expect(merged[0].values == ["kcal_consumed": 900, "protein_g": 60, "carbs_g": 80, "fat_g": 30])
    }

    @Test func latestFibreAndSugarReadingIsDated() {
        #expect(HealthDailyTotals.latest(\.fiberG, in: Self.health) == HealthDatedValue(value: 28, date: "2026-09-27"))
        #expect(HealthDailyTotals.latest(\.sugarG, in: []) == nil)
    }

    @Test func feedPublishesAndReads() {
        let feed = HealthDailyTotalsFeed()
        #expect(feed.latest.isEmpty)
        feed.publish(Self.health)
        #expect(feed.latest == Self.health)
    }
}

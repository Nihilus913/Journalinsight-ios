import Testing
import JICore
@testable import JIFeatures

/// RG-43: "7 days vs your goal" drew one full-width bar (only logged days became x categories) and
/// no ±5 % band. The chart now has 7 fixed day slots and a y domain that always holds the band.
@Suite struct RG43NutritionWeekSlotsTests {
    private func row(_ date: String, _ kcal: Double?) -> NutritionDailyRow {
        NutritionDailyRow(date: date, kcalConsumed: kcal)
    }

    @Test func sevenSlotsEndingTodayEvenWithOneLoggedDay() {
        let slots = nutritionWeekSlots(days: [row("2026-09-30", 1384), row("2026-10-05", nil)], today: "2026-10-05")
        #expect(slots.count == 7)
        #expect(slots.map(\.date) == ["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05"])
        #expect(slots.map(\.label) == ["T", "W", "T", "F", "S", "S", "M"])
        #expect(slots.compactMap(\.kcal) == [1384])
        #expect(Set(slots.map(\.date)).count == 7)   // unique x categories
    }

    @Test func yDomainAlwaysContainsTheBand() {
        let top = nutritionWeekYTop(kcals: [1384], goal: 1935)
        #expect(top >= 1935 * 1.05)
        #expect(nutritionWeekYTop(kcals: [3000], goal: 1935) >= 3000)
        #expect(nutritionWeekYTop(kcals: [], goal: nil) > 0)
    }
}

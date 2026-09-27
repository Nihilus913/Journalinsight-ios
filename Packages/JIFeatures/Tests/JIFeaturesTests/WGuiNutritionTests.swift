import Testing
import JICore
@testable import JIFeatures

// W-GUI M2 — Nutrition (05) + Meal detail (38): meal rows, the ±5 % band, captions.
@Test func mealRowCarriesItemsKcalAndProtein() {
    let row = mealTimelineRow(slot: "breakfast", items: [NutritionMealItem(name: "Skyr", kcal: 320, proteinG: 40), NutritionMealItem(name: "Oats", kcal: 226, proteinG: 10)])
    #expect(row.title == "Breakfast")
    #expect(row.subtitle == "Skyr, Oats")
    #expect(row.trailing == "546 kcal · 50 g P")
    let empty = mealTimelineRow(slot: "dinner", items: [])
    #expect(empty.subtitle == "— No data" && empty.trailing == "—")
}

@Test func weekBandAndAverageAreHonest() {
    #expect(nutritionWeekBand(goal: 1617)?.lowerBound == 1617 * 0.95)
    #expect(nutritionWeekBand(goal: nil) == nil)
    let days = [NutritionDailyRow(date: "2026-09-20", kcalConsumed: 1500), NutritionDailyRow(date: "2026-09-21", kcalConsumed: 1700),
                NutritionDailyRow(date: "2026-09-22", kcalConsumed: 400)]
    #expect(nutritionWeekAverageText(days: days, today: "2026-09-22") == "7-day avg 1600 · today so far")
    #expect(nutritionWeekAverageText(days: [days[2]], today: "2026-09-22") == nil)
    #expect(nutritionGoalAlignCaption.hasPrefix("Logging stays in YAZIO"))
    #expect(mealDetailYazioCaption.contains("does not log"))
}

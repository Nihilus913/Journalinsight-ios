import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-FIX11 H2-12: "MEALS TODAY" on a past day. H2-13: "7-day avg 1348 · today so far" averaged
// 24 Sep (outside the 25 Sep–1 Oct bars) and excluded today while saying "today so far".

@Test func mealsHeaderNamesThePickedDay() {
    #expect(nutritionMealsTitle(selected: "2026-10-01", today: "2026-10-01") == "Meals today")
    #expect(nutritionMealsTitle(selected: "2026-09-28", today: "2026-10-01") == "Meals · Monday")
}

@Test func weekAverageUsesTheBarsWindow() {
    let days = [NutritionDailyRow(date: "2026-09-24", kcalConsumed: 1183.1),
                NutritionDailyRow(date: "2026-09-29", kcalConsumed: 1383.8),
                NutritionDailyRow(date: "2026-09-30", kcalConsumed: 1478.6),
                NutritionDailyRow(date: "2026-09-25"), NutritionDailyRow(date: "2026-09-26"),
                NutritionDailyRow(date: "2026-09-27"), NutritionDailyRow(date: "2026-09-28"),
                NutritionDailyRow(date: "2026-10-01", kcalConsumed: 300)]
    #expect(nutritionWeekAverageText(days: days, today: "2026-10-01") == "Avg 1431 kcal · 2 logged days before today")
}

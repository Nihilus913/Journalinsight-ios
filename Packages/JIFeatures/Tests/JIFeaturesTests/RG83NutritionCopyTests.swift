import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-FIX-P3 RG-83 (B-99): Nutrition copy — one meals-source wording on every day, "so far" only
// for today, the method sheet's step numbers equal width (monospacedDigit, view-only).
@Suite struct RG83NutritionCopyTests {

    @Test func oneMealsSourceWordingOnEveryDay() {
        #expect(nutritionReadOnlyNote(source: .hub) == nutritionReadOnlyNote(source: .appleHealth))
        #expect(nutritionReadOnlyNote(source: nil) == nutritionReadOnlyNote(source: .hub))
        #expect(nutritionReadOnlyNote.contains("Meals come from YAZIO"))
        #expect(mealTimelineEmptyText == "No meals from YAZIO yet for this day.")
    }

    @Test func soFarOnlyForTodayNotOnAPastDay() {
        let row = DietQualityFixtures.incompleteRow
        let past = dietQualityPresentation(date: row.date, hubRow: row, health: nil, proteinGoal: 180, kcalGoal: 1935,
                                           today: "2026-10-06")
        #expect(past.rows[0].detail == "3.0 g")
        #expect(!past.rows.contains { $0.detail.contains("so far") })
        let today = dietQualityPresentation(date: row.date, hubRow: row, health: nil, proteinGoal: 180, kcalGoal: 1935,
                                            today: row.date)
        #expect(today.rows[0].detail == "3.0 g so far")
    }
}

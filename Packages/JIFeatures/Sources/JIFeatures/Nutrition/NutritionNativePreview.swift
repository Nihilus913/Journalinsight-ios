import SwiftUI
import JICore
import JIDesign

/// §8.5 fixture provider for the Nutrition registry entries — the sweep never reaches a hub.
struct L5NutritionFixtureProvider: NutritionProviding {
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { L5NutritionFixtures.day }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { L5NutritionFixtures.week }
    func logFood(_ body: LogFoodBody) async throws -> LogFoodResult { throw HubError.unauthorized }
    func deleteLogItem(itemId: String, date: String?) async throws {}
}

nonisolated enum L5NutritionFixtures {
    static let date = "2026-09-21"

    static let day = NutritionDayDetail(
        date: date,
        total: NutritionDayTotal(kcal: 2180, kcalGoal: 2400, proteinG: 168, carbsG: 214, fatG: 71, mealsLogged: 3),
        breakdown: NutritionDayBreakdown(breakfast: 520, lunch: 647, dinner: 780, snack: 233),
        items: [
            "breakfast": [NutritionMealItem(name: "Skyr, oats, berries", amountG: 420, kcal: 520, proteinG: 44, carbsG: 61, fatG: 9)],
            "lunch": [NutritionMealItem(name: "Rice, lentils, chicken, broccoli", amountG: 560, kcal: 526, proteinG: 48, carbsG: 58, fatG: 11),
                      NutritionMealItem(name: "Whey scoop", amountG: 30, kcal: 111, proteinG: 24, carbsG: 2, fatG: 1)],
            "dinner": [NutritionMealItem(name: "Salmon, potato, salad", amountG: 610, kcal: 780, proteinG: 46, carbsG: 63, fatG: 38)],
            "snack": [NutritionMealItem(name: "Banana", amountG: 120, kcal: 105, proteinG: 1, carbsG: 27, fatG: 0)],
        ]
    )

    static let week: [NutritionDailyRow] = [
        NutritionDailyRow(date: "2026-09-15", kcalConsumed: 2310, kcalGoal: 2400, mealsLogged: 4),
        NutritionDailyRow(date: "2026-09-16", kcalConsumed: 2050, kcalGoal: 2400, mealsLogged: 3),
        NutritionDailyRow(date: "2026-09-17", kcalConsumed: nil, kcalGoal: 2400, mealsLogged: nil),
        NutritionDailyRow(date: "2026-09-18", kcalConsumed: 2620, kcalGoal: 2400, mealsLogged: 5),
        NutritionDailyRow(date: "2026-09-19", kcalConsumed: 2400, kcalGoal: 2400, mealsLogged: 4),
        NutritionDailyRow(date: "2026-09-20", kcalConsumed: 1980, kcalGoal: 2400, mealsLogged: 3),
        NutritionDailyRow(date: date, kcalConsumed: 2180, kcalGoal: 2400, mealsLogged: 3),
    ]
}

/// §8.5 registry entry "Nutrition" — the cards `NutritionView.loaded` composes, over the fixture.
struct NutritionNativePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NutritionWeekStrip(days: L5NutritionFixtures.week, selectedDate: L5NutritionFixtures.date) { _ in }
            JISectionHeader("Today")
            MacroSummaryCard(day: L5NutritionFixtures.day)
            JISectionHeader("Meals")
            MealTimeline(day: L5NutritionFixtures.day)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .readableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JITheme.native.color(.bg))
    }
}

/// §8.5 registry entry "Nutrition log" — the +Log sheet's body.
struct NutritionLogNativePreview: View {
    @State private var model = LogSheetViewModel(provider: L5NutritionFixtureProvider())

    var body: some View {
        LogSheet(model: model).nativeContent
    }
}

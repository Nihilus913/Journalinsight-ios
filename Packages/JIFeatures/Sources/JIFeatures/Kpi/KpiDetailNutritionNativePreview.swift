import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entry "KPI detail nutrition" — protein selected, 28 fixture days, carbs missing,
/// and fixture user goals with no carbs goal (so both a goal and "Set your goal" show). B-73:
/// fixture values standing in for goals a user typed; JI ships none.
struct KpiDetailNutritionNativePreview: View {
    private static let rows: [NutritionDailyRow] = (1...28).map { d in
        NutritionDailyRow(date: String(format: "2026-08-%02d", d), kcalConsumed: 1550 + Double(d * 5), kcalGoal: nil,
                          proteinG: 110 + Double(d), carbsG: nil, fatG: 48 + Double(d % 6), mealsLogged: 3)
    }
    private static let goals = NutritionGoalsSnapshot(macros: MacroGoals(kcal: KcalGoal(goalKcal: 1700, basis: .includesDeficit), proteinG: 155, fatG: 55))
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Board: the source line with the "Last synced" pill (a fixed fixture time).
            KpiDetailSourceLine(subtitle: kpiSourceSubtitle(.protein),
                                fetchedAt: Date(timeIntervalSince1970: 1_790_158_440), showsSynced: true)
            KpiNutritionPanel(rows: Self.rows, macro: .protein)
        }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(JITheme.native.color(.bg))
            .jiTheme(.native)
            .environment(\.nutritionGoals, Self.goals)
    }
}

import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entry "KPI detail nutrition" — protein selected, 28 fixture days, carbs missing,
/// and a fixture goals document with no carbs goal (so both "goal" and "— No data" cells show).
struct KpiDetailNutritionNativePreview: View {
    private static let rows: [NutritionDailyRow] = (1...28).map { d in
        NutritionDailyRow(date: String(format: "2026-08-%02d", d), kcalConsumed: 1550 + Double(d * 5), kcalGoal: nil,
                          proteinG: 110 + Double(d), carbsG: nil, fatG: 48 + Double(d % 6), mealsLogged: 3)
    }
    private static let goals = NutritionGoal(kcalGoal: 1700, proteinG: 155, carbsG: nil, fatG: 55)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Board: the source line with the "Last synced" pill (a fixed fixture time).
            KpiDetailSourceLine(subtitle: kpiSourceSubtitle(.protein),
                                fetchedAt: Date(timeIntervalSince1970: 1_790_158_440), showsSynced: true)
            KpiNutritionPanel(rows: Self.rows, goals: Self.goals, macro: .protein)
        }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(JITheme.native.color(.bg))
            .jiTheme(.native)
    }
}

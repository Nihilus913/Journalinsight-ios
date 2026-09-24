import SwiftUI
import JICore
import JIDesign

/// §8.5 registry entry "KPI detail nutrition" — protein selected, 28 fixture days, carbs missing.
struct KpiDetailNutritionNativePreview: View {
    private static let rows: [NutritionDailyRow] = (1...28).map { d in
        NutritionDailyRow(date: String(format: "2026-08-%02d", d), kcalConsumed: 1550 + Double(d * 5), kcalGoal: nil,
                          proteinG: 110 + Double(d), carbsG: nil, fatG: 48 + Double(d % 6), mealsLogged: 3)
    }
    var body: some View {
        KpiNutritionPanel(rows: Self.rows, macro: .protein)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(JITheme.native.color(.bg))
            .jiTheme(.native)
    }
}

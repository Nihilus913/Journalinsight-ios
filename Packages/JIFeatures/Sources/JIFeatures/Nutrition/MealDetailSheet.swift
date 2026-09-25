import SwiftUI
import JICore
import JIDesign

public nonisolated let nutritionReadOnlyNote = "Read-only. JI shows what Apple Health holds; log meals in YAZIO or any app that writes to Health. JI has no food database and never logs food."

public nonisolated struct MealDetail: Equatable, Sendable {
    public let slot: String, title: String, items: [NutritionMealItem]
    public let kcal: Double?, protein: Double?, carbs: Double?, fat: Double?
}

public nonisolated func mealDetail(slot: String, items: [NutritionMealItem]) -> MealDetail {
    func sum(_ f: (NutritionMealItem) -> Double?) -> Double? {
        let v = items.compactMap(f); return v.isEmpty ? nil : v.reduce(0, +)
    }
    let titles = ["breakfast": "Breakfast", "lunch": "Lunch", "dinner": "Dinner", "snack": "Snack"]
    return MealDetail(slot: slot, title: titles[slot] ?? slot.capitalized, items: items,
                      kcal: sum(\.kcal), protein: sum(\.proteinG), carbs: sum(\.carbsG), fat: sum(\.fatG))
}

/// The four macro rows. A missing sum is "— No data" (rule 5: never a bare dash, never a zero).
public nonisolated func mealDetailRows(_ detail: MealDetail) -> [(title: String, value: String, role: JIColorRole)] {
    // W-FIX3 C-d: each row in its macro role (protein = `.protein`), as the rings and KPIs use.
    [("Calories", jiValueOrReasonText(detail.kcal, decimals: 0, unit: "kcal"), nutritionKcalTintRole),
     ("Protein", jiValueOrReasonText(detail.protein, decimals: 0, unit: "g"), .protein),
     ("Carbs", jiValueOrReasonText(detail.carbs, decimals: 0, unit: "g"), .carbs),
     ("Fat", jiValueOrReasonText(detail.fat, decimals: 0, unit: "g"), .fat)]
}

/// B-57 W1 (v11 change 2): the old +Log sheet, now a read-only Meal detail. One action: Done.
public struct MealDetailSheet: View {
    public nonisolated static let actionTitles = ["Done"]
    let detail: MealDetail
    @Environment(\.dismiss) private var dismiss
    private let theme = JITheme.native

    public init(detail: MealDetail) { self.detail = detail }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(detail.title)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("meal-detail-done") } }
        }
        .jiTheme(.native)
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder var content: some View {
        List {
            Section {
                Label("Read-only · \(JIExplainers.nutritionSourceLabel)", systemImage: "lock")
                    .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("meal-detail-readonly")
            }
            Section(detail.title) {
                row("Source", JIExplainers.nutritionSourceLabel, role: .muted)
                ForEach(mealDetailRows(detail), id: \.title) { r in row(r.title, r.value, role: r.role) }
            }
            Section {
                ForEach(Array(detail.items.enumerated()), id: \.offset) { _, item in
                    JIRow(title: item.name) { Text(jiValueOrReasonText(item.kcal, decimals: 0, unit: "kcal")) }
                }
            } footer: {
                Text("To change it, edit the entry in YAZIO; JI updates on the next sync. JI does not log or edit food.")
            }
        }
        .jiNativeFormChrome()
    }

    private func row(_ title: String, _ value: String, role: JIColorRole) -> some View {
        HStack { Text(title).foregroundStyle(theme.color(.text)); Spacer(); Text(value).foregroundStyle(theme.color(value.hasPrefix("—") ? .muted : role)) }
            .jiFont(.body)
            .accessibilityElement(children: .combine)
    }
}

/// §8.5 registry entry "Meal detail".
struct MealDetailNativePreview: View {
    var body: some View {
        MealDetailSheet(detail: mealDetail(slot: "breakfast", items: L5NutritionFixtures.day.items["breakfast"] ?? [])).content
            .jiTheme(.native)
    }
}

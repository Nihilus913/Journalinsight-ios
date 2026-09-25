import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/MealTimeline.tsx`) — the day's logged items,
/// grouped by daytime in the RN oracle's fixed order.
public struct MealTimeline: View {
    let day: NutritionDayDetail?
    let onSelectMeal: ((MealDetail) -> Void)?

    private static let order: [String] = ["breakfast", "lunch", "dinner", "snack"]
    private static let labels: [String: String] = ["breakfast": "Breakfast", "lunch": "Lunch", "dinner": "Dinner", "snack": "Snack"]

    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    public init(day: NutritionDayDetail?, onSelectMeal: ((MealDetail) -> Void)? = nil) { self.day = day; self.onSelectMeal = onSelectMeal }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                // B-33: the screen's `JISectionHeader("Meals")` carries the group title now —
                // an in-card repeat of it read as two headers in the sweep.
                if let day, !day.items.isEmpty {
                    ForEach(mealsInOrder(day), id: \.slot) { meal in
                        Button { onSelectMeal?(mealDetail(slot: meal.slot, items: meal.items)) } label: {
                            mealSection(slot: meal.slot, items: meal.items)
                        }
                        .buttonStyle(.pressableScale)
                        .disabled(onSelectMeal == nil)
                    }
                } else {
                    Text("No meals in Apple Health yet for this day.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("meal-timeline-empty")
                }
            }
        }
    }

    private func mealsInOrder(_ day: NutritionDayDetail) -> [(slot: String, items: [NutritionMealItem])] {
        let known = Self.order.compactMap { slot -> (String, [NutritionMealItem])? in
            guard let items = day.items[slot], !items.isEmpty else { return nil }
            return (slot, items)
        }
        let extras = day.items.keys.filter { !Self.order.contains($0) }.sorted()
            .compactMap { slot -> (String, [NutritionMealItem])? in
                guard let items = day.items[slot], !items.isEmpty else { return nil }
                return (slot, items)
            }
        return known + extras
    }

    private func mealSection(slot: String, items: [NutritionMealItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.labels[slot] ?? slot.capitalized).jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(.text))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("meal-row-\(slot)")
            // §2b.2: each logged item is a 44-pt inset-grouped row.
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Group { if typeSize.isAccessibilitySize {
                    // W-FIX3 BUG-33: at AX sizes a name beside its kcal broke mid-word
                    // ("Schink-/en"); the kcal takes its own line under the whole name.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).jiFont(.body).foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: mealItemKcalText(item.kcal)).jiFont(.body).foregroundStyle(theme.color(.muted))
                    }
                    .frame(maxWidth: .infinity, minHeight: JIRow<EmptyView>.minHeight, alignment: .leading)
                    .accessibilityElement(children: .combine)
                } else {
                    JIRow(title: item.name, systemImage: "fork.knife", tint: theme.color(.info)) {
                        // W-FIX3 BUG-36: the same rounding as My KPIs / KpiDetail / the Meal sheet.
                        Text(verbatim: mealItemKcalText(item.kcal))
                            .accessibilityLabel(mealItemKcalText(item.kcal))
                    }
                } }
                .accessibilityLabel(item.name)
                if idx != items.count - 1 { Divider().overlay(theme.color(.hairlineNested)).padding(.leading, 40) }
            }
        }
    }
}

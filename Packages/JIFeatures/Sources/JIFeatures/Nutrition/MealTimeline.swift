import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/MealTimeline.tsx`) — the day's logged items,
/// grouped by daytime in the RN oracle's fixed order.
public struct MealTimeline: View {
    let day: NutritionDayDetail?

    private static let order: [String] = ["breakfast", "lunch", "dinner", "snack"]
    private static let labels: [String: String] = ["breakfast": "Breakfast", "lunch": "Lunch", "dinner": "Dinner", "snack": "Snack"]

    @Environment(\.jiTheme) private var theme
    public init(day: NutritionDayDetail?) { self.day = day }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                // B-33: the screen's `JISectionHeader("Meals")` carries the group title now —
                // an in-card repeat of it read as two headers in the sweep.
                if let day, !day.items.isEmpty {
                    ForEach(mealsInOrder(day), id: \.slot) { meal in
                        mealSection(slot: meal.slot, items: meal.items)
                    }
                } else {
                    Text("No meals logged yet for this day.").jiFont(.footnote).foregroundStyle(theme.color(.muted))
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
                JIRow(title: item.name, systemImage: "fork.knife", tint: theme.color(.info)) {
                    Text(item.kcal.map { "\(Int($0)) kcal" } ?? "—")
                        .accessibilityLabel(item.kcal.map { "\(Int($0)) kcal" } ?? "no calorie data")
                }
                .accessibilityLabel(item.name)
                if idx != items.count - 1 { Divider().overlay(theme.color(.hairlineNested)).padding(.leading, 40) }
            }
        }
    }
}

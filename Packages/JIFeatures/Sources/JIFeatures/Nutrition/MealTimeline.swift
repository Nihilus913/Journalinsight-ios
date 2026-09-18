import SwiftUI
import JICore
import JIDesign

/// (W3a-L2, mirrors `mobile/src/components/nutrition/MealTimeline.tsx`) — the day's logged items,
/// grouped by daytime in the RN oracle's fixed order.
public struct MealTimeline: View {
    let day: NutritionDayDetail?

    private static let order: [String] = ["breakfast", "lunch", "dinner", "snack"]
    private static let labels: [String: String] = ["breakfast": "Breakfast", "lunch": "Lunch", "dinner": "Dinner", "snack": "Snack"]

    public init(day: NutritionDayDetail?) { self.day = day }

    public var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                Text("Meals").font(.caption).foregroundStyle(JIColor.muted).textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                if let day, !day.items.isEmpty {
                    ForEach(mealsInOrder(day), id: \.slot) { meal in
                        mealSection(slot: meal.slot, items: meal.items)
                    }
                } else {
                    Text("No meals logged yet for this day.").font(.footnote).foregroundStyle(JIColor.muted)
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
            Text(Self.labels[slot] ?? slot.capitalized).font(.footnote.weight(.bold)).foregroundStyle(JIColor.text)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("meal-row-\(slot)")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.name).font(.footnote).foregroundStyle(JIColor.text).lineLimit(1)
                        .accessibilityLabel(item.name)
                    Spacer()
                    Text(item.kcal.map { "\(Int($0)) kcal" } ?? "—").font(.caption).foregroundStyle(JIColor.muted)
                        .accessibilityLabel(item.kcal.map { "\(Int($0)) kcal" } ?? "no calorie data")
                }
            }
        }
    }
}

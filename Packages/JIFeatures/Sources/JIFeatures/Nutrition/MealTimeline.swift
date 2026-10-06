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
        Surface(level: 1, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // W-GUI M2 (mockup 05): one row per meal — the slot, its items, "kcal · g P" and a
                // chevron into the read-only detail (which lists the items).
                if let day, !day.items.isEmpty {
                    let meals = mealsInOrder(day)
                    ForEach(Array(meals.enumerated()), id: \.element.slot) { index, meal in
                        if index > 0 { JIRowDivider().padding(.leading, 0) }
                        let row = mealTimelineRow(slot: meal.slot, items: meal.items)
                        Button { onSelectMeal?(mealDetail(slot: meal.slot, items: meal.items)) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: JISpacing.s3) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                                        .accessibilityIdentifier("meal-row-\(meal.slot)")
                                    Text(row.subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: JISpacing.s2)
                                Text(row.trailing).jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.text))
                                    .monospacedDigit().multilineTextAlignment(.trailing)
                                if onSelectMeal != nil {
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                        .foregroundStyle(theme.color(.mutedNested)).accessibilityHidden(true)
                                }
                            }
                            .padding(.vertical, JIRowMetrics.verticalPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressableScale)
                        .disabled(onSelectMeal == nil)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(row.title), \(row.trailing). \(row.subtitle)")
                    }
                } else {
                    Text(mealTimelineEmptyText).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .padding(.vertical, JIRowMetrics.verticalPadding)
                        .accessibilityIdentifier("meal-timeline-empty")
                }
            }
            .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
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
}

/// W-FIX-P3 RG-83: the meal list is always YAZIO's (via the hub; Health holds day sums only),
/// so the empty state names that one source on every day.
public nonisolated let mealTimelineEmptyText = "No meals from YAZIO yet for this day."

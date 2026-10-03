import SwiftUI
import JICore
import JIDesign

/// W-FIX11 H2-14: meal items always come from the hub's YAZIO rows (Health has no per-item food).
public nonisolated let mealDetailSourceLabel = "YAZIO via the hub"

/// W-FIX11 H2-14: the footer names the source the day's numbers came from.
public nonisolated func nutritionReadOnlyNote(source: NutritionDataSource?) -> String {
    source == .hub
        ? "Read-only. JI shows what YAZIO sent to the hub; log meals in YAZIO. JI has no food database and never logs food."
        : nutritionReadOnlyNote
}

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
        .jiSheetGround()
    }
    /// W-GUI M2 (mockup 38): read-only pill · the kcal numeral with the slot line · three macro
    /// tiles of one size · the items · the YAZIO caption. Every number is the day's own (rule 5).
    @ViewBuilder var content: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                Label("Read-only · \(mealDetailSourceLabel)", systemImage: "lock")
                    .jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.muted))
                    .padding(.horizontal, JISpacing.s3).padding(.vertical, 6)
                    .background(theme.color(.control), in: RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous).strokeBorder(theme.color(.hairlineOuter), lineWidth: 1))
                    .accessibilityIdentifier("meal-detail-readonly")
                Surface(level: 1, padding: JISpacing.cardPadding) {
                    VStack(alignment: .leading, spacing: JISpacing.s3) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: nutritionWholeText(detail.kcal)).jiNumeral(.numeralMedium, weight: .heavy)
                                .foregroundStyle(theme.color(detail.kcal == nil ? .muted : nutritionKcalTintRole))
                            Text(detail.kcal == nil ? JIMissingReason.noData.rawValue : "kcal").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        }
                        Text("\(detail.title) · \(mealDetailSourceLabel)").jiFont(.caption).foregroundStyle(theme.color(.muted))
                        HStack(spacing: JISpacing.tileGap) {
                            macroTile("Protein", detail.protein, role: .protein)
                            macroTile("Carbs", detail.carbs, role: .carbs)
                            macroTile("Fat", detail.fat, role: .fat)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !detail.items.isEmpty {
                    JISectionHeader("Items")
                    Surface(level: 1, padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(detail.items.enumerated()), id: \.offset) { index, item in
                                if index > 0 { JIRowDivider().padding(.leading, 0) }
                                JIRow(title: item.name) { Text(jiValueOrReasonText(item.kcal, decimals: 0, unit: "kcal")) }
                            }
                        }
                        .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
                    }
                }
                Text(mealDetailYazioCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
    }
    private func macroTile(_ label: String, _ value: Double?, role: JIColorRole) -> some View {
        JITile(family: .factTile) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: nutritionWholeText(value)).jiNumeral(.numeralSmall, tint: value == nil ? .muted : role)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if value != nil { Text("g").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(jiValueOrReasonText(value, decimals: 0, unit: "g"))")
    }
    private func row(_ title: String, _ value: String, role: JIColorRole) -> some View {
        HStack { Text(title).foregroundStyle(theme.color(.text)); Spacer(); Text(value).foregroundStyle(theme.color(value.hasPrefix("—") ? .muted : role)) }
            .jiFont(.body)
            .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// §8.5 registry entry "Meal detail".
struct MealDetailNativePreview: View {
    var body: some View {
        MealDetailSheet(detail: mealDetail(slot: "breakfast", items: L5NutritionFixtures.day.items["breakfast"] ?? [])).content
            .jiTheme(.native)
    }
}
#endif

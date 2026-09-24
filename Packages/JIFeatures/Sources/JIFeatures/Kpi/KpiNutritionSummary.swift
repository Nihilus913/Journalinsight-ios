import SwiftUI
import JIDesign
import Foundation
import JICore

public nonisolated struct KpiMacroSummary: Equatable, Sendable {
    public let latestDate: String?, latest: Double?, avg7: Double?, avg28: Double?
}

public nonisolated func kpiMacroValue(_ row: NutritionDailyRow, _ macro: KpiMetricId) -> Double? {
    switch macro {
    case .kcal: row.kcalConsumed
    case .protein: row.proteinG
    case .carbs: row.carbsG
    case .fat: row.fatG
    default: nil
    }
}

public nonisolated func kpiMacroSummary(rows: [NutritionDailyRow], macro: KpiMetricId) -> KpiMacroSummary {
    let series = rows.map { (date: $0.date, value: kpiMacroValue($0, macro)) }
    let latest = series.sorted { $0.date > $1.date }.first { $0.value != nil }
    return KpiMacroSummary(latestDate: latest?.date, latest: latest?.value ?? nil,
                           avg7: trendAverage(series, days: 7), avg28: trendAverage(series, days: 28))
}

/// The goal / latest / 7 d / 28 d cells of one table row. JI-owned macro goals arrive in W2, so
/// the goal cell is "— No data" until then; a missing actual is "— No data" too (rule 5).
public nonisolated func kpiMacroTableCells(_ s: KpiMacroSummary, decimals: Int, goal: Double? = nil) -> [String] {
    [goal, s.latest, s.avg7, s.avg28].map { jiValueOrReasonText($0, decimals: decimals) }
}

/// B-57 W1 KpiDetailNutrition: macro picker, the 7-day NormalBar (normal W3, goal W2), and the
/// goal / latest / 7 d / 28 d table over `NutritionDailyRow`s.
struct KpiNutritionPanel: View {
    let rows: [NutritionDailyRow]
    @State var macro: KpiMetricId
    private let theme = JITheme.native

    var body: some View {
        let s = kpiMacroSummary(rows: rows, macro: macro)
        let def = KpiMetrics.def(macro)
        VStack(alignment: .leading, spacing: 16) {
            Picker("Macro", selection: $macro) {
                ForEach([KpiMetricId.kcal, .protein, .carbs, .fat], id: \.self) { Text(KpiMetrics.def($0).label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("kpi-detail-macro-picker")
            HStack(alignment: .firstTextBaseline) {
                Text("7 days vs 28 days").jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                Spacer()
                NormalBarLegend()
            }
            Surface {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Last 7 days").jiFont(.body).foregroundStyle(theme.color(.text))
                        Spacer()
                        Text(jiValueText(s.avg7, decimals: def.decimals)).jiFont(.body, weight: .bold).foregroundStyle(theme.color(.text))
                        if s.avg7 != nil { Text("\(def.unit) a day").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
                    }
                    NormalBar(value: s.avg7, normal: nil, unit: def.unit, decimals: def.decimals, tint: metricTintRole(macro.rawValue))
                }
            }
            JISectionHeader("All macros · goal vs actual")
            Surface {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow { Text("Macro").gridColumnAlignment(.leading); Text("Goal"); Text("Latest"); Text("7 d"); Text("28 d") }
                        .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    ForEach([KpiMetricId.kcal, .protein, .carbs, .fat], id: \.self) { m in
                        let ms = kpiMacroSummary(rows: rows, macro: m)
                        let d = KpiMetrics.def(m).decimals
                        GridRow {
                            Text(KpiMetrics.def(m).label).foregroundStyle(theme.color(metricTintRole(m.rawValue))).gridColumnAlignment(.leading)
                            ForEach(Array(kpiMacroTableCells(ms, decimals: d).enumerated()), id: \.offset) { _, cell in
                                Text(cell).foregroundStyle(theme.color(cell.hasPrefix("—") ? .muted : .text))
                                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .jiFont(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("kpi-detail-macro-table")
            }
        }
    }
}

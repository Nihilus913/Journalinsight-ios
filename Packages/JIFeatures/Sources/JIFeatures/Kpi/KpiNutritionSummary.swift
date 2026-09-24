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
public nonisolated func kpiMacroTableCells(_ s: KpiMacroSummary, decimals: Int, unit: String? = nil, goal: Double? = nil) -> [String] {
    [goal, s.latest, s.avg7, s.avg28].map { jiValueOrReasonText($0, decimals: decimals, unit: unit) }
}

/// The table's unit per macro: grams carry "g" (board: "127 g"); calories are bare numbers.
public nonisolated func kpiMacroTableUnit(_ macro: KpiMetricId) -> String? { macro == .kcal ? nil : "g" }

/// The table's day column header: the newest day when every macro that has one shares it
/// ("22 SEP"), else "LATEST" — never a date some of the cells are not from.
public nonisolated func kpiMacroDayHeader(_ summaries: [KpiMacroSummary]) -> String {
    let dates = Set(summaries.compactMap(\.latestDate))
    let parts = dates.count == 1 ? dates.first!.split(separator: "-").compactMap { Int($0) } : []
    guard parts.count == 3, (1...12).contains(parts[1]) else { return "LATEST" }
    let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    return "\(parts[2]) \(months[parts[1] - 1])"
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
            Surface { KpiMacroTable(rows: rows) }
        }
    }
}

/// B-57 W1 fixer: the board's goal-vs-actual table (`2 Monitor/04 KpiDetailNutrition.png`) —
/// MACRO · GOAL · <day> · 7 D · 28 D across the full card width, one line per cell ("— No data"
/// stays whole instead of breaking over two lines). At accessibility sizes five columns cannot
/// fit, so each macro becomes its own labelled block.
struct KpiMacroTable: View {
    let rows: [NutritionDailyRow]
    private let theme = JITheme.native
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let macros: [KpiMetricId] = [.kcal, .protein, .carbs, .fat]

    var body: some View {
        let summaries = Self.macros.map { kpiMacroSummary(rows: rows, macro: $0) }
        let headers = ["GOAL", kpiMacroDayHeader(summaries), "7 D", "28 D"]
        Group {
            if typeSize.isAccessibilitySize { stacked(summaries, headers: headers) } else { grid(summaries, headers: headers) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("kpi-detail-macro-table")
    }

    private func cells(_ i: Int, _ s: KpiMacroSummary) -> [String] {
        let m = Self.macros[i]
        return kpiMacroTableCells(s, decimals: KpiMetrics.def(m).decimals, unit: kpiMacroTableUnit(m))
    }

    private func grid(_ summaries: [KpiMacroSummary], headers: [String]) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 0) {
            GridRow {
                Text("MACRO").frame(maxWidth: .infinity, alignment: .leading).gridColumnAlignment(.leading)
                ForEach(headers, id: \.self) { Text($0) }
            }
            .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted)).lineLimit(1)
            .padding(.bottom, 10)
            ForEach(Array(summaries.enumerated()), id: \.offset) { i, s in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    Text(KpiMetrics.def(Self.macros[i]).label).jiFont(.footnote, weight: .semibold)
                        .foregroundStyle(theme.color(metricTintRole(Self.macros[i].rawValue)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(cells(i, s).enumerated()), id: \.offset) { c, cell in
                        Text(cell).jiFont(.caption)
                            .foregroundStyle(theme.color(cell.hasPrefix("—") ? .muted : (c == 0 ? .muted : .text)))
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.vertical, 10)
            }
        }
    }

    private func stacked(_ summaries: [KpiMacroSummary], headers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(summaries.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 4) {
                    Text(KpiMetrics.def(Self.macros[i]).label).jiFont(.body, weight: .semibold)
                        .foregroundStyle(theme.color(metricTintRole(Self.macros[i].rawValue)))
                    ForEach(Array(zip(headers, cells(i, s)).enumerated()), id: \.offset) { _, pair in
                        HStack(alignment: .firstTextBaseline) {
                            Text(pair.0).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            Spacer(minLength: 8)
                            Text(pair.1).jiFont(.body).foregroundStyle(theme.color(pair.1.hasPrefix("—") ? .muted : .text))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                if i < summaries.count - 1 { Divider() }
            }
        }
    }
}

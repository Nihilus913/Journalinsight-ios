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

/// The goal / latest / 7 d / 28 d cells of one table row. The goal is the user's goals document;
/// a goal not set, or a missing actual, is "— No data" (rule 5).
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

// MARK: - B-57 W1 r4: the board's hero, its status line and the Up / Down / Steady line

/// The board's calorie tint (orange) on the nutrition screens (KpiDetailNutrition, WeeklyPlan,
/// Energy). B-57 W1 r5: the JIDesign macro role `.kcal` (a metric colour, never a verdict) —
/// no longer the verdict role `.reduced` borrowed for it.
public nonisolated let nutritionKcalTintRole: JIColorRole = .kcal

/// The numeral / label tint for one macro: the JIDesign macro roles (kcal / protein / carbs / fat).
public nonisolated func kpiMacroTintRole(_ macro: KpiMetricId) -> JIColorRole {
    macro == .kcal ? nutritionKcalTintRole : metricTintRole(macro.rawValue)
}

/// The user's own goal for one macro, from the goals document (Goals › setup). `nil` = not set.
public nonisolated func kpiMacroGoal(_ goal: NutritionGoal?, _ macro: KpiMetricId) -> Double? {
    switch macro {
    case .kcal: goal?.kcalGoal
    case .protein: goal?.proteinG
    case .carbs: goal?.carbsG
    case .fat: goal?.fatG
    default: nil
    }
}

/// Beside the hero numeral: "/ 155 g goal", or "no goal set" — never an invented goal.
public nonisolated func kpiMacroHeroGoalText(goal: Double?, unit: String, decimals: Int) -> String {
    guard let goal, goal.isFinite else { return "no goal set" }
    return "/ \(jiNumber(goal, decimals)) \(unit) goal"
}

/// Within this share of the goal a day reads "On goal" (1549 against 1617 is on goal on the board).
public nonisolated let kpiMacroOnGoalTolerance = 0.05

public nonisolated struct KpiMacroHeroStatus: Equatable, Sendable {
    public let word: String
    public let role: JIColorRole
    public let symbolName: String
}

/// "22 Sep" from "2026-09-22"; the raw string when it is not a date.
public nonisolated func kpiShortDayText(_ iso: String) -> String {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, (1...12).contains(parts[1]) else { return iso }
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(parts[2]) \(months[parts[1] - 1])"
}

/// The hero's status line: the newest day against the user's goal. `nil` when no goal is set (the
/// hero already says "no goal set"); "— No data" when there is no reading. Protein over its goal
/// is good news (`.go`); calories, carbs or fat over it are not (`.reduced`).
public nonisolated func kpiMacroHeroStatus(value: Double?, goal: Double?, date: String?, macro: KpiMetricId,
                                           unit: String, decimals: Int) -> KpiMacroHeroStatus? {
    guard let value, value.isFinite else {
        return KpiMacroHeroStatus(word: "— \(JIMissingReason.noData.rawValue)", role: .muted, symbolName: "minus")
    }
    guard let goal, goal.isFinite, goal > 0 else { return nil }
    let diff = value - goal
    if abs(diff) / goal <= kpiMacroOnGoalTolerance {
        return KpiMacroHeroStatus(word: JISignalStatus.onGoal.word, role: .go, symbolName: "checkmark")
    }
    let on = date.map { " on \(kpiShortDayText($0))" } ?? ""
    let amount = "\(jiNumber(abs(diff), decimals)) \(unit)"
    if diff < 0 {
        return KpiMacroHeroStatus(word: "\(JISignalStatus.belowGoal.word) · \(amount) short\(on)", role: .reduced, symbolName: "arrow.down")
    }
    return KpiMacroHeroStatus(word: "\(JISignalStatus.aboveGoal.word) · \(amount) over\(on)",
                              role: macro == .protein ? .go : .reduced, symbolName: "arrow.up")
}

/// The line under the 7-day bar: the 7-day average against the 28-day one, in words.
public nonisolated func kpiMacroTrendLine(avg7: Double?, avg28: Double?) -> String {
    let tail = "Days with nothing in Apple Health are skipped, not counted as zero."
    let word: String
    switch trendDirection(recent: avg7, baseline: avg28) {
    case .up: word = "Up"
    case .down: word = "Down"
    case .flat: word = "Steady"
    case .unknown: return "— \(JIMissingReason.noData.rawValue) yet to compare. \(tail)"
    }
    return "\(word) against your 28-day average. \(tail)"
}

/// B-57 W1 KpiDetailNutrition: macro picker, the 7-day NormalBar (normal W3, goal W2), and the
/// goal / latest / 7 d / 28 d table over `NutritionDailyRow`s.
struct KpiNutritionPanel: View {
    let rows: [NutritionDailyRow]
    /// The user's goals document (`nil` = not loaded / not set → "no goal set", "— No data").
    var goals: NutritionGoal? = nil
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
            KpiMacroHero(summary: s, macro: macro, goal: kpiMacroGoal(goals, macro))
            // AX3: title and legend stack instead of truncating.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { compareTitle.fixedSize(); Spacer(); NormalBarLegend() }
                VStack(alignment: .leading, spacing: 4) { compareTitle.fixedSize(horizontal: false, vertical: true); NormalBarLegend() }
            }
            Surface {
                VStack(alignment: .leading, spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { last7Label.fixedSize(); Spacer(); last7Value(s, def).fixedSize() }
                        VStack(alignment: .leading, spacing: 2) { last7Label.fixedSize(horizontal: false, vertical: true); last7Value(s, def) }
                    }
                    // Goal tick (W2) and normal band (W3) are left for later waves.
                    NormalBar(value: s.avg7, normal: nil, unit: def.unit, decimals: def.decimals, tint: kpiMacroTintRole(macro))
                }
            }
            Text(kpiMacroTrendLine(avg7: s.avg7, avg28: s.avg28))
                .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("kpi-detail-macro-trend")
            JISectionHeader("All macros · goal vs actual")
            Surface { KpiMacroTable(rows: rows, goals: goals) }
            // Board: "Put on a widget" — the KPI widget is chosen in the system widget editor
            // (`SelectKpiIntent`); the app has no in-app pin action, so the row is left out.
        }
    }
}

extension KpiNutritionPanel {
    fileprivate var compareTitle: some View {
        Text("7 days vs 28 days").jiFont(.cardTitle).foregroundStyle(theme.color(.text))
    }
    fileprivate var last7Label: some View { Text("Last 7 days").jiFont(.body).foregroundStyle(theme.color(.text)) }
    fileprivate func last7Value(_ s: KpiMacroSummary, _ def: KpiMetricDef) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(jiValueText(s.avg7, decimals: def.decimals)).jiFont(.body, weight: .bold)
                .foregroundStyle(theme.color(s.avg7 == nil ? .muted : kpiMacroTintRole(macro)))
            if s.avg7 != nil { Text("\(def.unit) a day").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
        }
    }
}

/// Board hero: the newest day's value large in the macro's tint, "/ 155 g goal" (or "no goal
/// set") beside it, and the status line under it.
struct KpiMacroHero: View {
    let summary: KpiMacroSummary
    let macro: KpiMetricId
    let goal: Double?
    private let theme = JITheme.native

    var body: some View {
        let def = KpiMetrics.def(macro)
        let status = kpiMacroHeroStatus(value: summary.latest, goal: goal, date: summary.latestDate, macro: macro,
                                        unit: def.unit, decimals: def.decimals)
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { number(def); goalText(def) }
                VStack(alignment: .leading, spacing: 2) { number(def); goalText(def) }
            }
            if let status {
                Group {
                    if status.word.hasPrefix("—") { Text(status.word) } else { Label(status.word, systemImage: status.symbolName) }
                }
                .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(status.role))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kpi-detail-macro-status")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kpi-detail-macro-hero")
    }

    private func number(_ def: KpiMetricDef) -> some View {
        Text(jiValueText(summary.latest, decimals: def.decimals))
            .jiNumeral(.numeralDisplay, weight: .heavy)
            .foregroundStyle(theme.color(summary.latest == nil ? .muted : kpiMacroTintRole(macro)))
            .accessibilityIdentifier("kpi-detail-value")
    }

    private func goalText(_ def: KpiMetricDef) -> some View {
        Text(kpiMacroHeroGoalText(goal: goal, unit: def.unit, decimals: def.decimals))
            .jiFont(.body).foregroundStyle(theme.color(.muted))
    }
}

/// B-57 W1 fixer: the board's goal-vs-actual table (`2 Monitor/04 KpiDetailNutrition.png`) —
/// MACRO · GOAL · <day> · 7 D · 28 D across the full card width, one line per cell ("— No data"
/// stays whole instead of breaking over two lines). At accessibility sizes five columns cannot
/// fit, so each macro becomes its own labelled block.
struct KpiMacroTable: View {
    let rows: [NutritionDailyRow]
    var goals: NutritionGoal? = nil
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
        return kpiMacroTableCells(s, decimals: KpiMetrics.def(m).decimals, unit: kpiMacroTableUnit(m), goal: kpiMacroGoal(goals, m))
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
                        .foregroundStyle(theme.color(kpiMacroTintRole(Self.macros[i])))
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
                        .foregroundStyle(theme.color(kpiMacroTintRole(Self.macros[i])))
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

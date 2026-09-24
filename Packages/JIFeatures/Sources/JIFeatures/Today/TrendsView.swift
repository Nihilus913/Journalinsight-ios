import SwiftUI
import JICore
import JIDesign

/// B-57 W1 Trends: one NormalBar per KPI (fill = 7-day value; the 28-day normal band arrives in
/// W3, goal ticks in W2). Entry: Day footer "Trends". Filters: All / Recovery / Nutrition / Body.
public nonisolated enum TrendsFilter: String, CaseIterable, Sendable, Identifiable {
    case all = "All", recovery = "Recovery", nutrition = "Nutrition", body = "Body"
    public var id: String { rawValue }
}

public nonisolated struct TrendsCardModel: Identifiable, Sendable, Equatable {
    public let id: String, group: TrendsFilter, name: String, systemImage: String
    public let unit: String?, decimals: Int, value: Double?, tint: JIColorRole, status: JISignalStatus
}

public nonisolated func trendsCards(recovery: [RecoveryDay], daily: [DailyKpiRow], averages: GateAverages?) -> [TrendsCardModel] {
    func rec(_ f: @escaping (RecoveryDay) -> Double?) -> Double? {
        trendAverage(recovery.map { (date: $0.date, value: f($0)) }, days: trendRecentDays)
    }
    func day(_ key: String) -> Double? {
        trendAverage(daily.map { (date: $0.date, value: $0.values[key] ?? nil) }, days: trendRecentDays)
    }
    func card(_ id: String, _ group: TrendsFilter, _ name: String, _ symbol: String, _ value: Double?, unit: String?, decimals: Int = 0) -> TrendsCardModel {
        // W1: a value exists but its personal normal is not computed yet (W3) → "Calibrating".
        TrendsCardModel(id: id, group: group, name: name, systemImage: symbol, unit: unit, decimals: decimals, value: value,
                        tint: metricTintRole(id), status: value == nil ? .missing(.noData) : .missing(.calibrating))
    }
    return [
        card("hrv", .recovery, "HRV", "waveform.path.ecg", rec(\.hrvWeeklyAvg), unit: "ms"),
        card("rhr", .recovery, "Resting HR", "heart", rec(\.rhrBpm), unit: "bpm"),
        card("sleep", .recovery, "Sleep", "moon", rec { $0.sleepDurationSec.map { $0 / 3600 } }, unit: "h", decimals: 1),
        card("load", .recovery, "Load", "bolt", rec(\.acwr), unit: nil, decimals: 2),
        card("kcal", .nutrition, "Calories", "flame", averages?.avgKcal7d, unit: "kcal"),
        card("protein", .nutrition, "Protein", "fork.knife", averages?.avgProtein7d, unit: "g"),
        // Today holds no carbs/fat series; W2 reads dietary carbs/fat from Apple Health.
        card("carbs", .nutrition, "Carbs", "leaf", nil, unit: "g"),
        card("fat", .nutrition, "Fat", "drop", nil, unit: "g"),
        card("weight", .body, "Weight", "scalemass", day("weight_kg"), unit: "kg", decimals: 1),
        card("steps", .body, "Steps", "figure.walk", day("steps"), unit: nil),
    ]
}

public nonisolated func trendsCards(_ cards: [TrendsCardModel], filter: TrendsFilter) -> [TrendsCardModel] {
    filter == .all ? cards : cards.filter { $0.group == filter }
}

public struct TrendsView: View {
    let recovery: [RecoveryDay], daily: [DailyKpiRow], averages: GateAverages?
    let onSelectKpi: ((String) -> Void)?
    @State private var filter: TrendsFilter = .all
    @Environment(\.jiTheme) private var theme

    public init(recovery: [RecoveryDay], daily: [DailyKpiRow], averages: GateAverages?, onSelectKpi: ((String) -> Void)? = nil) {
        self.recovery = recovery; self.daily = daily; self.averages = averages; self.onSelectKpi = onSelectKpi
    }

    public var body: some View {
        let all = trendsCards(recovery: recovery, daily: daily, averages: averages)
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your last 7 days against your normal from the 28 days before.")
                    .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                Picker("Filter", selection: $filter) {
                    ForEach(TrendsFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("trends.filter")
                ForEach([TrendsFilter.recovery, .nutrition, .body].filter { filter == .all || filter == $0 }) { group in
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.rawValue).jiFont(.cardTitle).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
                        Spacer()
                        if group == .nutrition { Text("7 d vs 28 d").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                    }
                    Columns(minimum: 150, spacing: 12) {
                        ForEach(trendsCards(all, filter: group)) { c in card(c) }
                    }
                }
                NormalBarLegend()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .navigationTitle("Trends")
    }

    private func card(_ c: TrendsCardModel) -> some View {
        Button { onSelectKpi?(c.id) } label: {
            Surface(level: 1) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(c.name, systemImage: c.systemImage).jiFont(.subheadline, weight: .semibold)
                        .foregroundStyle(theme.color(c.value == nil ? .muted : c.tint))
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(jiValueText(c.value, decimals: c.decimals)).jiNumeral(.numeralCompact, tint: c.value == nil ? .muted : c.tint)
                        if c.value != nil, let u = c.unit { Text(u).jiFont(.caption).foregroundStyle(theme.color(.muted)) }
                    }
                    Label(c.status.word, systemImage: c.status.symbolName).jiFont(.caption, weight: .semibold)
                        .foregroundStyle(theme.color(c.status.role))
                    NormalBar(value: c.value, normal: nil, unit: c.unit, decimals: c.decimals, tint: c.tint, showsCaption: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.pressableScale)
        .disabled(onSelectKpi == nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trends.card.\(c.id)")
    }
}

/// §8.5 registry entry "Trends" — fixed series, no hub.
struct TrendsNativePreview: View {
    private static let recovery: [RecoveryDay] = (0..<28).map { i in
        RecoveryDay(date: String(format: "2026-09-%02d", i + 1), sleepScore: 80, sleepDurationSec: 26_000 + Double(i * 60),
                    rhrBpm: nil, bodyBatteryAvg: nil, readinessScore: 72, acwr: nil, hrvWeeklyAvg: 48 + Double(i % 5))
    }
    var body: some View {
        TrendsView(recovery: Self.recovery, daily: [], averages: nil)
            .jiTheme(.native)
            .environment(\.jiOffscreenRender, true)
    }
}

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

/// `averages` is no longer read (W-FIX1 BUG-04: its `avg_*_7d` follow the hub's `window_days`);
/// the parameter stays so `TodayView`'s call site is unchanged.
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
        // W-FIX1 BUG-06: nightly HRV only, never the hub's 7-day `hrv_weekly_avg` mix.
        card("hrv", .recovery, "HRV", "waveform.path.ecg", rec { KpiMetrics.nightlyHrvMs($0) }, unit: "ms"),
        card("rhr", .recovery, "Resting HR", "heart", rec(\.rhrBpm), unit: "bpm"),
        card("sleep", .recovery, "Sleep", "moon", rec { $0.sleepDurationSec.map { $0 / 3600 } }, unit: "h", decimals: 1),
        // W-FIX1 BUG-12: an ACWR of 0.00 is the hub's invented ratio (no load source) → "—".
        card("load", .recovery, "Load", "bolt", rec { KpiMetrics.honestAcwr($0.acwr) }, unit: nil, decimals: 2),
        // W-FIX1 BUG-04/BUG-32: the macros are the mean of the last 7 daily rows (`gate.daily`),
        // the same value KpiDetail's "Last 7 days" shows — not the hub's `avg_*_7d`, which is
        // computed over the whole `window_days` (28 here), and carbs/fat are no longer "No data".
        card("kcal", .nutrition, "Calories", "flame", day("kcal_consumed"), unit: "kcal"),
        card("protein", .nutrition, "Protein", "fork.knife", day("protein_g"), unit: "g"),
        card("carbs", .nutrition, "Carbs", "leaf", day("carbs_g"), unit: "g"),
        card("fat", .nutrition, "Fat", "drop", day("fat_g"), unit: "g"),
        card("weight", .body, "Weight", "scalemass", day("weight_kg"), unit: "kg", decimals: 1),
        card("steps", .body, "Steps", "figure.walk", day("steps"), unit: nil),
    ]
}

/// B-73: a nutrition card's goal tick = the user's own goal for that macro; nil (no tick) when
/// unset or for a non-nutrition card.
public nonisolated func trendsGoal(_ card: TrendsCardModel, _ goals: NutritionGoalsSnapshot) -> Double? {
    guard card.group == .nutrition, let id = KpiMetricId(rawValue: card.id) else { return nil }
    return goals.goal(for: id)
}

public nonisolated func trendsCards(_ cards: [TrendsCardModel], filter: TrendsFilter) -> [TrendsCardModel] {
    filter == .all ? cards : cards.filter { $0.group == filter }
}

/// B-57 W1 Trends "Edit": which cards show is a per-device UI pref (`@AppStorage`, comma-joined
/// ids — the same shape as Recovery's squares). Editing shows every card with a hide/show badge.
public nonisolated func trendsHiddenIds(_ raw: String) -> Set<String> {
    Set(raw.split(separator: ",").map(String.init))
}
public nonisolated func trendsShownCards(_ cards: [TrendsCardModel], hiddenRaw: String, editing: Bool) -> [TrendsCardModel] {
    editing ? cards : cards.filter { !trendsHiddenIds(hiddenRaw).contains($0.id) }
}
public nonisolated func trendsToggleHidden(_ raw: String, id: String) -> String {
    var hidden = trendsHiddenIds(raw)
    if hidden.contains(id) { hidden.remove(id) } else { hidden.insert(id) }
    return hidden.sorted().joined(separator: ",")
}

public struct TrendsView: View {
    let recovery: [RecoveryDay], daily: [DailyKpiRow], averages: GateAverages?
    let onSelectKpi: ((String) -> Void)?
    @State private var filter: TrendsFilter = .all
    @State private var editing = false
    @AppStorage("trends.hidden") private var hiddenRaw = ""
    @Environment(\.jiTheme) private var theme
    /// B-57 W2 (B-73): the user's goals — the nutrition cards' goal tick (unset → no tick).
    @Environment(\.nutritionGoals) private var nutritionGoals

    public init(recovery: [RecoveryDay], daily: [DailyKpiRow], averages: GateAverages?, onSelectKpi: ((String) -> Void)? = nil) {
        self.recovery = recovery; self.daily = daily; self.averages = averages; self.onSelectKpi = onSelectKpi
    }

    public var body: some View {
        let all = trendsCards(recovery: recovery, daily: daily, averages: averages)
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your last 7 days against your normal from the 28 days before.")
                    .jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
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
                        ForEach(trendsShownCards(trendsCards(all, filter: group), hiddenRaw: hiddenRaw, editing: editing)) { c in card(c) }
                    }
                }
                NormalBarLegend()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .navigationTitle("Trends")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editing ? "Done" : "Edit") { editing.toggle() }.accessibilityIdentifier("trends.edit")
            }
        }
    }

    private func card(_ c: TrendsCardModel) -> some View {
        let hidden = trendsHiddenIds(hiddenRaw).contains(c.id)
        return Button {
            if editing { hiddenRaw = trendsToggleHidden(hiddenRaw, id: c.id) } else { onSelectKpi?(c.id) }
        } label: {
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
                    NormalBar(value: c.value, normal: nil, goal: trendsGoal(c, nutritionGoals), unit: c.unit, decimals: c.decimals, tint: c.tint, showsCaption: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(editing && hidden ? 0.45 : 1)
            .overlay(alignment: .topTrailing) {
                if editing {
                    Image(systemName: hidden ? "plus" : "minus").font(.caption.weight(.bold))
                        .foregroundStyle(theme.color(hidden ? .bg : .text))
                        .frame(width: 24, height: 24).background(theme.color(hidden ? .info : .control), in: Circle())
                        .padding(8).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.pressableScale)
        .disabled(!editing && onSelectKpi == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(editing ? (hidden ? "Shows this card" : "Hides this card") : "")
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

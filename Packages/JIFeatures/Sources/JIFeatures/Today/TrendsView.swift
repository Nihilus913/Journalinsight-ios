import SwiftUI
import JICore
import JICompute
import JIDesign

/// B-57 W1 Trends: one NormalBar per KPI (fill = 7-day value; B-57 W3: the band is the 28-day
/// personal normal of the card's own series, `KpiNormal`; W2: goal ticks). Entry: Day footer "Trends". Filters: All / Recovery / Nutrition / Body.
public nonisolated enum TrendsFilter: String, CaseIterable, Sendable, Identifiable {
    case all = "All", recovery = "Recovery", nutrition = "Nutrition", body = "Body"
    public var id: String { rawValue }
}

public nonisolated struct TrendsCardModel: Identifiable, Sendable, Equatable {
    public let id: String, group: TrendsFilter, name: String, systemImage: String
    public let unit: String?, decimals: Int, value: Double?, tint: JIColorRole, status: JISignalStatus
    /// B-57 W3: the card's 28-day personal normal (nil = Calibrating — never a fallback band).
    public var normal: PersonalNormalResult? = nil
    /// W-FIX6 F6-9: "as of 19 Sep" when the value is an older reading (no reading in the last 7
    /// days); nil when the value is the 7-day mean.
    public var asOf: String? = nil
}

/// `averages` is no longer read (W-FIX1 BUG-04: its `avg_*_7d` follow the hub's `window_days`);
/// the parameter stays so `TodayView`'s call site is unchanged. `today` = the phone's local day
/// (the normal's window is today−34 … today−7). W-FIX6 F6-8: `load` = the gate-input Load (7-day
/// minutes + band, `RecoveryInsightService.loadReading`) — the same number Today's Load square and
/// the KPI detail show; ACWR stays the fallback for a hub that serves one.
public nonisolated func trendsCards(recovery: [RecoveryDay], daily: [DailyKpiRow], averages: GateAverages?,
                                    today: String = RecoveryInsightService.localDayKey(Date()),
                                    load: RecoveryLoadReading? = nil) -> [TrendsCardModel] {
    typealias Series = (value: Double?, points: [(date: String, value: Double?)])
    func rec(_ f: @escaping (RecoveryDay) -> Double?) -> Series {
        let pts = recovery.map { (date: $0.date, value: f($0)) }
        return (trendAverage(pts, days: trendRecentDays), pts)
    }
    func day(_ key: String) -> Series {
        let pts = daily.map { (date: $0.date, value: $0.values[key] ?? nil) }
        return (trendAverage(pts, days: trendRecentDays), pts)
    }
    func card(_ id: String, _ group: TrendsFilter, _ name: String, _ symbol: String, _ s: Series, unit: String?, decimals: Int = 0) -> TrendsCardModel {
        // B-57 W3: the band is the normal of the series the card averages; under 14 values it
        // stays "Calibrating" (a value) or "No data" (none).
        let normal = KpiNormal.make(points: s.points, today: today).normal
        return TrendsCardModel(id: id, group: group, name: name, systemImage: symbol, unit: unit, decimals: decimals, value: s.value,
                               tint: metricTintRole(id), status: KpiNormal.status(value: s.value, normal: normal), normal: normal)
    }
    /// W-FIX6 F6-8: an ACWR the hub really sent keeps the card; else the gate-input minutes.
    func loadCard() -> TrendsCardModel {
        let acwr = card("load", .recovery, "Load", "bolt", rec { KpiMetrics.honestAcwr($0.acwr) }, unit: nil, decimals: 2)
        guard acwr.value == nil, let load else { return acwr }
        return TrendsCardModel(id: "load", group: .recovery, name: "Load", systemImage: "bolt", unit: recoveryLoadUnit, decimals: 0,
                               value: load.minutes.rounded(), tint: metricTintRole("load"),
                               status: KpiNormal.status(value: load.minutes, normal: load.normal), normal: load.normal)
    }
    /// W-FIX6 F6-9: weigh-ins are sparse — with none in the last 7 days the card shows the last one
    /// with its date (the Today square's rule), never "No data" while a weight exists.
    func weightCard() -> TrendsCardModel {
        var c = card("weight", .body, "Weight", "scalemass", day("weight_kg"), unit: "kg", decimals: 1)
        guard c.value == nil,
              let last = daily.filter({ ($0.values["weight_kg"] ?? nil)?.isFinite == true }).max(by: { $0.date < $1.date }),
              let kg = last.values["weight_kg"] ?? nil else { return c }
        let normal = c.normal
        c = TrendsCardModel(id: c.id, group: c.group, name: c.name, systemImage: c.systemImage, unit: c.unit, decimals: c.decimals,
                            value: kg, tint: c.tint, status: KpiNormal.status(value: kg, normal: normal), normal: normal,
                            asOf: kpiAsOfLabel(valueDate: last.date, today: today))
        return c
    }
    return [
        // W-FIX1 BUG-06: nightly HRV only, never the hub's 7-day `hrv_weekly_avg` mix.
        card("hrv", .recovery, "HRV", "waveform.path.ecg", rec { KpiMetrics.nightlyHrvMs($0) }, unit: "ms"),
        card("rhr", .recovery, "Resting HR", "heart", rec(\.rhrBpm), unit: "bpm"),
        card("sleep", .recovery, "Sleep", "moon", rec { $0.sleepDurationSec.map { $0 / 3600 } }, unit: "h", decimals: 1),
        // W-FIX1 BUG-12: an ACWR of 0.00 is the hub's invented ratio (no load source) → "—".
        loadCard(),
        // W-FIX1 BUG-04/BUG-32: the macros are the mean of the last 7 daily rows (`gate.daily`),
        // the same value KpiDetail's "Last 7 days" shows — not the hub's `avg_*_7d`, which is
        // computed over the whole `window_days` (28 here), and carbs/fat are no longer "No data".
        card("kcal", .nutrition, "Calories", "flame", day("kcal_consumed"), unit: "kcal"),
        card("protein", .nutrition, "Protein", "fork.knife", day("protein_g"), unit: "g"),
        card("carbs", .nutrition, "Carbs", "leaf", day("carbs_g"), unit: "g"),
        card("fat", .nutrition, "Fat", "drop", day("fat_g"), unit: "g"),
        weightCard(),
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
    /// W-FIX6 F6-8: the gate-input Load (the number Today's Load square shows).
    @Environment(\.recoveryInsight) private var recoveryInsight

    public init(recovery: [RecoveryDay], daily: [DailyKpiRow], averages: GateAverages?, onSelectKpi: ((String) -> Void)? = nil) {
        self.recovery = recovery; self.daily = daily; self.averages = averages; self.onSelectKpi = onSelectKpi
    }

    public var body: some View {
        let all = trendsCards(recovery: recovery, daily: daily, averages: averages, load: recoveryInsight?.loadReading)
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
                        // W-FIX7 fixer F7-5: every card of a group with a dated one reserves the line (equal tiles).
                        let shown = trendsShownCards(trendsCards(all, filter: group), hiddenRaw: hiddenRaw, editing: editing)
                        let reserveAsOf = trendsReservesAsOfLine(shown)
                        ForEach(shown) { c in card(c, reserveAsOf: reserveAsOf) }
                    }
                }
                NormalBarLegend()
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .readableColumn()
        }
        .jiPageGround()
        .jiGlassBackButton()
        .navigationTitle("Trends")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                JIGlassButton(editing ? "checkmark" : "pencil", label: editing ? "Done" : "Edit") { editing.toggle() }.accessibilityIdentifier("trends.edit")
            }
        }
    }

    private func card(_ c: TrendsCardModel, reserveAsOf: Bool) -> some View {
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
                    TrendsAsOfLine(card: c, reserve: reserveAsOf)
                    Label(c.status.word, systemImage: c.status.symbolName).jiFont(.caption, weight: .semibold)
                        .foregroundStyle(theme.color(c.status.role))
                    NormalBar(value: c.value, normal: c.normal?.range, median: c.normal?.median, goal: trendsGoal(c, nutritionGoals), unit: c.unit, decimals: c.decimals, tint: c.tint, showsCaption: false)
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

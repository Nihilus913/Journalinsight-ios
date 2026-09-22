import SwiftUI
import JICore
import JIDesign

/// B-42 (W-B46 L2) — one row of the Today **Trends** card: the metric's 7-day average against its
/// own 28-day baseline. Computed client-side over the series Today has already cached (`recovery`
/// + `gate.daily`), so the card costs no hub round-trip and needs no new route.
public nonisolated struct TodayTrend: Identifiable, Sendable, Equatable {
    public let id: String, name: String, unit: String?
    public let decimals: Int
    public let recent: Double?, baseline: Double?
    public let colorRole: JIColorRole

    public init(id: String, name: String, unit: String? = nil, decimals: Int = 0, recent: Double?, baseline: Double?, colorRole: JIColorRole) {
        self.id = id; self.name = name; self.unit = unit; self.decimals = decimals
        self.recent = recent; self.baseline = baseline; self.colorRole = colorRole
    }

    public var direction: JITrendDirection { trendDirection(recent: recent, baseline: baseline) }
}

/// The mean of the last `days` entries with a real value, oldest→newest by `date`. `nil` when the
/// window holds no value at all — never 0 (rule 5). Null days are skipped rather than counted, so
/// a half-tracked week still averages the days that exist instead of being dragged toward zero.
public nonisolated func trendAverage(_ points: [(date: String, value: Double?)], days: Int) -> Double? {
    let window = points.sorted { $0.date < $1.date }.suffix(days).compactMap(\.value)
    guard !window.isEmpty else { return nil }
    return window.reduce(0, +) / Double(window.count)
}

/// Apple Fitness's Trends block, over our KPIs: recent = the last 7 days, baseline = the last 28
/// (the recent week included — the baseline is the period average the week is read against, not a
/// disjoint earlier window, so a single good day cannot flip the comparison twice).
public nonisolated let trendRecentDays = 7
public nonisolated let trendBaselineDays = 28

/// The six trends the card shows, in reading order. Pure: everything comes from the two series
/// Today already holds. Load is ACWR (unitless, 2 dp) and Weight comes off `gate.daily`'s
/// `weight_kg` column, the same source `KpiMetrics` reads.
public nonisolated func todayTrends(recovery: [RecoveryDay], daily: [DailyKpiRow]) -> [TodayTrend] {
    func rec(_ value: @escaping (RecoveryDay) -> Double?) -> [(date: String, value: Double?)] {
        recovery.map { (date: $0.date, value: value($0)) }
    }
    func day(_ key: String) -> [(date: String, value: Double?)] {
        daily.map { (date: $0.date, value: $0.values[key] ?? nil) }
    }
    func trend(_ id: String, _ name: String, _ series: [(date: String, value: Double?)], unit: String? = nil, decimals: Int = 0, role: JIColorRole) -> TodayTrend {
        TodayTrend(id: id, name: name, unit: unit, decimals: decimals,
                   recent: trendAverage(series, days: trendRecentDays),
                   baseline: trendAverage(series, days: trendBaselineDays),
                   colorRole: role)
    }
    return [
        trend("hrv", "HRV", rec(\.hrvWeeklyAvg), unit: "ms", role: .info),
        trend("rhr", "Resting HR", rec(\.rhrBpm), unit: "bpm", role: .reduced),
        trend("sleep", "Sleep score", rec(\.sleepScore), role: .sleep),
        trend("steps", "Steps", day("steps"), role: .info),
        trend("load", "Load (ACWR)", rec(\.acwr), decimals: 2, role: .reduced),
        trend("weight", "Weight", day("weight_kg"), unit: "kg", decimals: 1, role: .muted),
    ]
}

/// The Today Trends card — Apple's two-column block (`docs/design/references/
/// 2026-09-22-apple-fitness-summary.png`), fed by `todayTrends`.
public struct TrendsCard: View {
    let trends: [TodayTrend]
    let onSelectKpi: ((String) -> Void)?
    @Environment(\.jiTheme) private var theme

    public init(trends: [TodayTrend], onSelectKpi: ((String) -> Void)? = nil) {
        self.trends = trends; self.onSelectKpi = onSelectKpi
    }

    public var body: some View {
        Surface(level: 1) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Trends").jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("7 d vs 28 d").jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                }
                Columns(minimum: 150, spacing: 14) {
                    ForEach(trends) { t in
                        let row = TrendRow(name: t.name, recent: t.recent, baseline: t.baseline,
                                           unit: t.unit, decimals: t.decimals, tint: theme.color(t.colorRole))
                        if let onSelectKpi {
                            Button { onSelectKpi(t.id) } label: { row }
                                .buttonStyle(.pressableScale)
                                .accessibilityIdentifier("today.trend.\(t.id)")
                        } else {
                            row.accessibilityIdentifier("today.trend.\(t.id)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today.trends")
    }
}

/// §8.5 registry entry "Trends card" — the shipping card over a fixed series, so the sweep renders
/// the same pixels on every run (no hub, no disk, no async load).
struct TrendsCardNativePreview: View {
    private static let recovery: [RecoveryDay] = (0..<28).map { i in
        let day: Int = i % 7
        let sleep: Double = [78, 81, 74, 88, 83, 79, 85][day]
        let rhr: Double = [54, 53, 55, 52, 53, 54, 52][day]
        let battery: Double = [61, 64, 58, 70, 66, 62, 68][day]
        let readiness: Double = [68, 71, 64, 79, 74, 70, 76][day]
        let acwr: Double = [1.02, 1.05, 1.11, 0.97, 1.01, 1.08, 1.04][day]
        let hrv: Double = [48, 50, 47, 53, 51, 49, 52][day] + Double(i) * 0.1
        return RecoveryDay(
            date: String(format: "2026-09-%02d", i + 1),
            sleepScore: sleep,
            sleepDurationSec: 25_200,
            rhrBpm: rhr,
            bodyBatteryAvg: battery,
            readinessScore: readiness,
            acwr: acwr,
            hrvWeeklyAvg: hrv
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            JISectionHeader("Today")
            TrendsCard(trends: todayTrends(recovery: Self.recovery, daily: []))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JITheme.native.color(.bg))
        .jiTheme(.native)
        .environment(\.jiOffscreenRender, true)
    }
}

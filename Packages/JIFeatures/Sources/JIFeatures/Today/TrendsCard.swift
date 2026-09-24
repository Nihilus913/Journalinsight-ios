import SwiftUI
import JICore
import JIDesign

/// B-42 (W-B46 L2) — one Today trend: the metric's 7-day average against its
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

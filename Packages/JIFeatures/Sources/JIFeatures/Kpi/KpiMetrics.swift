import Foundation
import JICore

/// W3b-L2 (P-kpi) — the universal KPI metric registry, ported from the oracle's
/// `mobile/src/lib/kpiMetrics.ts::KPI_METRICS`. One entry per metric the KPI list/detail screens
/// render; `source` says which existing (W3a) provider call backs its live value + history —
/// `HealthDataProvider.recovery`/`.gate` or `NutritionProviding.nutritionWeek` — no new hub route.
public nonisolated enum KpiMetricId: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case hrv, rhr, sleep, bodyBattery = "body_battery", readiness, acwr, weight, steps, kcal, protein, carbs, fat
    public var id: String { rawValue }
}

public nonisolated enum KpiSource: Sendable, Equatable { case recovery, nutritionDaily, gate }

public nonisolated struct KpiMetricDef: Sendable, Equatable {
    public let id: KpiMetricId
    public let label: String
    public let unit: String
    public let decimals: Int
    public let source: KpiSource
    /// Matches the backing FastAPI router's `window_days` Query cap (oracle's `maxLiveWindowDays`)
    /// — 90 for `gate`-sourced metrics (`app/planning/router.py`'s `Query(le=90)`), 365 for the rest.
    public let maxLiveWindowDays: Int
    /// `plan.kpi_target.metric` values this KPI's gate rule(s) live under — empty when no rule
    /// currently targets this metric (never fabricated; the row simply shows no target).
    public let targetMetricKeys: [String]
}

/// Pure data + arithmetic, no UI state — `nonisolated` so it's callable from a plain `@Test` (JIFeatures
/// defaults new decls to `@MainActor`, CONTEXT-IOS-FOUNDATION.md §3).
public nonisolated enum KpiMetrics {
    public static let all: [KpiMetricDef] = [
        KpiMetricDef(id: .hrv, label: "HRV", unit: "ms", decimals: 0, source: .recovery, maxLiveWindowDays: 365, targetMetricKeys: []),
        KpiMetricDef(id: .rhr, label: "Resting HR", unit: "bpm", decimals: 0, source: .recovery, maxLiveWindowDays: 365, targetMetricKeys: []),
        KpiMetricDef(id: .sleep, label: "Sleep score", unit: "", decimals: 0, source: .recovery, maxLiveWindowDays: 365, targetMetricKeys: ["sleep_score_7d"]),
        KpiMetricDef(id: .bodyBattery, label: "Body battery", unit: "", decimals: 0, source: .recovery, maxLiveWindowDays: 365, targetMetricKeys: []),
        KpiMetricDef(id: .readiness, label: "Readiness", unit: "", decimals: 0, source: .recovery, maxLiveWindowDays: 365, targetMetricKeys: []),
        KpiMetricDef(id: .acwr, label: "Training load (ACWR)", unit: "", decimals: 2, source: .recovery, maxLiveWindowDays: 365, targetMetricKeys: ["acwr"]),
        KpiMetricDef(id: .weight, label: "Weight", unit: "kg", decimals: 1, source: .gate, maxLiveWindowDays: 90, targetMetricKeys: []),
        KpiMetricDef(id: .steps, label: "Steps", unit: "", decimals: 0, source: .gate, maxLiveWindowDays: 90, targetMetricKeys: []),
        KpiMetricDef(id: .kcal, label: "Calories", unit: "kcal", decimals: 0, source: .nutritionDaily, maxLiveWindowDays: 365, targetMetricKeys: ["avg_kcal_7d"]),
        KpiMetricDef(id: .protein, label: "Protein", unit: "g", decimals: 0, source: .nutritionDaily, maxLiveWindowDays: 365, targetMetricKeys: ["avg_protein_7d"]),
        KpiMetricDef(id: .carbs, label: "Carbs", unit: "g", decimals: 0, source: .nutritionDaily, maxLiveWindowDays: 365, targetMetricKeys: []),
        KpiMetricDef(id: .fat, label: "Fat", unit: "g", decimals: 0, source: .nutritionDaily, maxLiveWindowDays: 365, targetMetricKeys: []),
    ]

    public static func def(_ id: KpiMetricId) -> KpiMetricDef {
        // Force-unwrap is safe: `all` has exactly one entry per `KpiMetricId.allCases` (tested).
        all.first { $0.id == id }!
    }

    /// The metric's current headline number — latest non-nil day across whichever source it's
    /// keyed to. `gateAverages` (from `GateResponse.averages`) is consulted only for `.weight`,
    /// mirroring the oracle's G0-5 same-source fallback (WeightCard's own trailing-7d average)
    /// when no individual `dailyRows` entry carries a real weigh-in for that day.
    public static func value(
        for id: KpiMetricId,
        recovery: [RecoveryDay],
        nutrition: [NutritionDailyRow],
        dailyRows: [DailyKpiRow],
        gateAverages: GateAverages?
    ) -> Double? {
        latest(for: id, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows, gateAverages: gateAverages)?.value
    }

    /// B-46 device feedback 3 (ROOT CAUSE): the headline used to read the row with the LATEST
    /// DATE and then take the field off it — so the moment a day exists with a nil HRV/RHR (no
    /// Garmin sync since 09-18, but the row is there), the number read "—" while the chart right
    /// under it plotted a full series. The current value is the latest NON-NULL reading, and it
    /// carries the date it was taken on so the screen can say "as of Sep 21" instead of silently
    /// presenting an old number as today's.
    public static func latest(
        for id: KpiMetricId,
        recovery: [RecoveryDay],
        nutrition: [NutritionDailyRow],
        dailyRows: [DailyKpiRow],
        gateAverages: GateAverages?
    ) -> (value: Double, date: String)? {
        let series = history(for: id, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows)
        if let hit = series.reversed().first(where: { $0.value != nil }), let value = hit.value {
            return (value, hit.date)
        }
        // Weight keeps the oracle's G0-5 same-source fallback (the gate's own trailing-7d
        // average) — an average, so it has no single day to be "as of".
        if id == .weight, let avg = gateAverages?.avgWeightKg { return (avg, "") }
        return nil
    }

    /// Kept for the two callers that want the raw same-day read (fixtures/tests); the screens use
    /// `latest(for:…)`.
    static func sameDayValue(
        for id: KpiMetricId,
        recovery: [RecoveryDay],
        nutrition: [NutritionDailyRow],
        dailyRows: [DailyKpiRow],
        gateAverages: GateAverages?
    ) -> Double? {
        switch id {
        case .hrv: return latestRecovery(recovery)?.hrvWeeklyAvg
        case .rhr: return latestRecovery(recovery)?.rhrBpm
        case .sleep: return latestRecovery(recovery)?.sleepScore
        case .bodyBattery: return latestRecovery(recovery)?.bodyBatteryAvg
        case .readiness: return latestRecovery(recovery)?.readinessScore
        case .acwr: return latestRecovery(recovery)?.acwr
        case .weight: return latestDailyValue(dailyRows, key: "weight_kg") ?? gateAverages?.avgWeightKg
        case .steps: return latestDailyValue(dailyRows, key: "steps")
        case .kcal: return latestNutrition(nutrition)?.kcalConsumed
        case .protein: return latestNutrition(nutrition)?.proteinG
        case .carbs: return latestNutrition(nutrition)?.carbsG
        case .fat: return latestNutrition(nutrition)?.fatG
        }
    }

    /// Oldest→newest series for the detail screen's Swift Charts trend — `nil` days pass through
    /// (never coerced to 0, rule 5) so the chart can skip them rather than dip to a false zero.
    public static func history(
        for id: KpiMetricId,
        recovery: [RecoveryDay],
        nutrition: [NutritionDailyRow],
        dailyRows: [DailyKpiRow]
    ) -> [(date: String, value: Double?)] {
        switch def(id).source {
        case .recovery:
            return recovery.sorted { $0.date < $1.date }.map { ($0.date, recoveryField($0, id)) }
        case .nutritionDaily:
            return nutrition.sorted { $0.date < $1.date }.map { ($0.date, nutritionField($0, id)) }
        case .gate:
            let key = id == .weight ? "weight_kg" : "steps"
            return dailyRows.sorted { $0.date < $1.date }.map { ($0.date, $0.values[key].flatMap { $0 }) }
        }
    }

    /// Every `plan.kpi_target` row whose `metric` matches this KPI's `targetMetricKeys`, formatted
    /// as `"< 1600"` / `"0.8–1.3"` (between) — joined when more than one rule shares the metric
    /// (e.g. `acwr`'s three rows). `nil` when nothing currently targets this metric.
    public static func targetText(for id: KpiMetricId, targets: [KpiTarget]) -> String? {
        let keys = Set(def(id).targetMetricKeys)
        guard !keys.isEmpty else { return nil }
        let matches = targets.filter { keys.contains($0.metric) }
        guard !matches.isEmpty else { return nil }
        return matches.map { t in
            if t.operator == "between", let hi = t.thresholdHi { return "\(formatNumber(t.threshold))–\(formatNumber(hi))" }
            return "\(t.operator) \(formatNumber(t.threshold))"
        }.joined(separator: "; ")
    }

    private static func recoveryField(_ d: RecoveryDay, _ id: KpiMetricId) -> Double? {
        switch id {
        case .hrv: d.hrvWeeklyAvg
        case .rhr: d.rhrBpm
        case .sleep: d.sleepScore
        case .bodyBattery: d.bodyBatteryAvg
        case .readiness: d.readinessScore
        case .acwr: d.acwr
        default: nil
        }
    }

    private static func nutritionField(_ n: NutritionDailyRow, _ id: KpiMetricId) -> Double? {
        switch id {
        case .kcal: n.kcalConsumed
        case .protein: n.proteinG
        case .carbs: n.carbsG
        case .fat: n.fatG
        default: nil
        }
    }

    private static func latestRecovery(_ rows: [RecoveryDay]) -> RecoveryDay? { rows.max { $0.date < $1.date } }
    private static func latestNutrition(_ rows: [NutritionDailyRow]) -> NutritionDailyRow? { rows.max { $0.date < $1.date } }

    private static func latestDailyValue(_ rows: [DailyKpiRow], key: String) -> Double? {
        rows.sorted { $0.date > $1.date }.compactMap { $0.values[key].flatMap { $0 } }.first
    }

    private static func formatNumber(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// Never renders a bare "0" for a missing value (CLAUDE.md rule 5) — an em dash instead.
public nonisolated func formatKpiValue(_ value: Double?, decimals: Int) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.precision(.fractionLength(decimals)))
}

/// B-46 device feedback 3: "as of Sep 21" — the date a fallback reading was actually taken on,
/// shown only when it is NOT the day being looked at. An empty/unparseable date (the weight
/// average fallback has none) produces nil, never a half-sentence.
public nonisolated func kpiAsOfLabel(valueDate: String?, today: String) -> String? {
    guard let valueDate, !valueDate.isEmpty, valueDate != today else { return nil }
    guard let date = trainingStripDate(valueDate) else { return nil }
    return "as of " + date.formatted(.dateTime.month(.abbreviated).day())
}

/// B-46 device feedback 4: the human sentence for a `plan.kpi_target` rule. `operator` is the
/// hub's own comparison string (`<`, `<=`, `>`, `>=`, `between`); anything unrecognised falls back
/// to a neutral phrasing rather than printing the raw symbol at the reader.
public nonisolated func kpiThresholdSentence(metricLabel: String, `operator` op: String) -> String {
    switch op {
    case "<", "<=": return "Alert when \(metricLabel) falls below"
    case ">", ">=": return "Alert when \(metricLabel) rises above"
    case "between": return "Alert when \(metricLabel) leaves the range starting at"
    default: return "Alert threshold for \(metricLabel)"
    }
}

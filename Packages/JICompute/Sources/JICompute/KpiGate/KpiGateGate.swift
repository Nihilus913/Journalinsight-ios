import Foundation

/// KPI / decision gate — Swift port of the pure logic in
/// `HealthTraining/app/planning/service.py` (DB loaders, queries and the
/// FastAPI router are deliberately out of scope), transliterated from the
/// frozen RN oracle `mobile/src/compute/kpiGate/gate.ts` and proven against
/// `kpi.golden.json` (582 cases generated from the live Python).
///
/// 1:1 function-name mapping (Python -> Swift):
///
///     _safe_float              -> safeFloat
///     _latest_acwr             -> latestAcwr
///     _compute_derived_metrics -> computeDerivedMetrics
///     compute_averages         -> computeAverages
///     _eval_rule               -> evalRule
///     _build_suggestions       -> buildSuggestions
///     evaluate_kpi_gates       -> evaluateKpiGates
///     is_tracked_day           -> isTrackedDay
///     evaluate_gate            -> evaluateGate

// MARK: - Constants

public nonisolated let defaultKpiConfig = KpiConfig(
    progressKcalRatioMin: 0.80,   // >= 80% of kcal_goal
    progressKcalRatioMax: 1.10,   // <= 110% of kcal_goal
    progressProteinPerKg: 2.0,    // g protein per kg body weight
    // Tracking-quality gate: a day counts as tracked only if it looks like a
    // genuinely logged day (strict-day definition, memory/feedback_tracking).
    trackingKcalMin: 1200,
    trackingMealsMin: 3,
    minTrackedDays: 4,
    countRuleFields: [
        "avg_kcal_7d": (field: "kcal_consumed", minDays: 5),
        "avg_protein_7d": (field: "protein_g", minDays: 5),
        "sleep_score_7d": (field: "sleep_score", minDays: 4),
    ]
)

/// Canonical `plan.kpi_target` seed, so the app has a working gate offline
/// before any server round-trip. These are literal DB rows: do not rename
/// `metric` or reorder them (order decides which rule fires first).
public nonisolated let defaultKpiRules: [KpiRule] = [
    KpiRule(metric: "acwr", operator: ">", threshold: 1.30, thresholdHi: nil,
            description: "REDUCE: overreaching"),
    KpiRule(metric: "avg_kcal_7d", operator: "<", threshold: 1600.00, thresholdHi: nil,
            description: "REDUCE: chronic underfueling"),
    KpiRule(metric: "avg_protein_7d", operator: "<", threshold: 130.00, thresholdHi: nil,
            description: "REDUCE: insufficient protein"),
    KpiRule(metric: "sleep_score_7d", operator: "<", threshold: 55.00, thresholdHi: nil,
            description: "REDUCE: poor sleep"),
    KpiRule(metric: "acwr", operator: "<", threshold: 0.80, thresholdHi: nil,
            description: "MAINTAIN: undertraining"),
    KpiRule(metric: "acwr", operator: "between", threshold: 0.80, thresholdHi: 1.30,
            description: "PROGRESS zone (combined with nutrition gates)"),
]

// MARK: - Pure helpers

/// `_safe_float`: coerce a value to a float, or `nil`.
///
/// Python's job here is the `Decimal -> float` coercion psycopg's NUMERIC
/// columns require; that boundary is already crossed by the JSON round-trip
/// (the generator writes `float(Decimal)`), so what survives is the
/// nil short-circuit and 1:1 call-site parity.
public nonisolated func safeFloat(_ v: Double?) -> Double? { v }

/// Every `[_safe_float(r.get(field)) for r in rows if ... is not None]`.
nonisolated func collect(_ rows: [KpiMetricRow], _ field: String) -> [Double] {
    var out: [Double] = []
    out.reserveCapacity(rows.count)
    for row in rows {
        if let v = safeFloat(row[field]) { out.append(v) }
    }
    return out
}

/// `_avg`: `round(sum(vals) / len(vals), 1)`, or `nil` for an empty list.
/// Summation is left-to-right, as in Python and the TS oracle.
nonisolated func avg(_ vals: [Double]) -> Double? {
    guard !vals.isEmpty else { return nil }
    var sum = 0.0
    for v in vals { sum += v }
    return pythonRound(sum / Double(vals.count), 1)
}

/// `_trend`: compare the first half against the second half.
nonisolated func trend(_ vals: [Double]) -> TrendDirection {
    guard vals.count >= 4 else { return .flat }
    let mid = vals.count / 2
    var firstSum = 0.0
    for v in vals[..<mid] { firstSum += v }
    var lastSum = 0.0
    for v in vals[mid...] { lastSum += v }
    let first = firstSum / Double(mid)
    let last = lastSum / Double(vals.count - mid)
    if first == 0 { return .flat }
    let pct = (last - first) / abs(first)
    if pct > 0.02 { return .up }
    if pct < -0.02 { return .down }
    return .flat
}

/// `_latest_acwr`, minus the same-day skip.
///
/// The Python original prefers the most recent COMPLETE (dated, not-today) row
/// because `core.training_load_daily`'s acute average reads artificially low
/// until today's session is synced. That branch needs `date.today()`, which
/// JICompute must not call (XC `CLAUDE.md` rule 8), and it is unreachable here:
/// the compute surface receives date-less rows (the golden generator strips
/// `date` from every row), so Python itself falls through to this same
/// "last non-nil value in list order" tail — which is also exactly what the TS
/// oracle does. A dated-row preference belongs in the caller that owns a clock.
nonisolated func latestAcwr(_ rows: [KpiMetricRow]) -> Double? {
    collect(rows, "acwr").last
}

// MARK: - Derived metrics

/// `_compute_derived_metrics`: the aggregates the rule table reads.
/// Returns `DerivedMetrics.empty` (Python's bare `{}`) for no rows.
public nonisolated func computeDerivedMetrics(_ metricsRows: [KpiMetricRow]) -> DerivedMetrics {
    guard !metricsRows.isEmpty else { return .empty }

    let acwrVals = collect(metricsRows, "acwr")
    let kcalVals = collect(metricsRows, "kcal_consumed")
    let proteinVals = collect(metricsRows, "protein_g")
    let sleepVals = collect(metricsRows, "sleep_score")
    let weightVals = collect(metricsRows, "weight_kg")
    let rhrVals = collect(metricsRows, "rhr_bpm")
    let stepsVals = collect(metricsRows, "steps")
    let bbVals = collect(metricsRows, "body_battery_avg")
    let kcalGoalVals = collect(metricsRows, "kcal_goal")
    let kcalBurnedVals = collect(metricsRows, "kcal_burned_active")

    let avgKcal = avg(kcalVals)
    let avgProtein = avg(proteinVals)
    let avgKcalGoal = avg(kcalGoalVals)
    let avgWeight = avg(weightVals)

    var avgKcalGoalRatio: Double?
    if let avgKcal, let avgKcalGoal, avgKcalGoal != 0 {
        avgKcalGoalRatio = pythonRound(avgKcal / avgKcalGoal, 3)
    }
    var proteinPerKg: Double?
    if let avgProtein, let avgWeight, avgWeight != 0 {
        proteinPerKg = pythonRound(avgProtein / avgWeight, 2)
    }
    var avgKcalDeficit: Double?
    if let avgKcal, let avgKcalGoal {
        avgKcalDeficit = pythonRound(avgKcalGoal - avgKcal, 1)
    }
    var estWeeklyWeightChangeKg: Double?
    if let avgKcalDeficit {
        estWeeklyWeightChangeKg = pythonRound(avgKcalDeficit * 7 / 7700, 2)
    }

    return DerivedMetrics(
        isEmpty: false,
        acwr: latestAcwr(metricsRows),
        avgKcal7d: avgKcal,
        avgProtein7d: avgProtein,
        sleepScore7d: avg(sleepVals),
        avgWeightKg: avgWeight,
        avgRhrBpm: avg(rhrVals),
        avgSteps: avg(stepsVals),
        avgBodyBattery: avg(bbVals),
        avgKcalBurned7d: avg(kcalBurnedVals),
        avgKcalGoalRatio: avgKcalGoalRatio,
        proteinPerKg: proteinPerKg,
        avgKcalDeficit7d: avgKcalDeficit,
        estWeeklyWeightChangeKg: estWeeklyWeightChangeKg,
        trends: TrendMap(
            kcal: trend(kcalVals),
            protein: trend(proteinVals),
            rhr: trend(rhrVals),
            sleep: trend(sleepVals),
            acwr: trend(acwrVals),
            bodyBattery: trend(bbVals),
            kcalBurned: trend(kcalBurnedVals)
        )
    )
}

/// `compute_averages`: `{**_empty, **derived}` plus the four aliases. Every key
/// is always present (nil when there is no data).
public nonisolated func computeAverages(_ dailyRows: [KpiMetricRow]) -> AveragesResult {
    let derived = computeDerivedMetrics(dailyRows)
    return AveragesResult(
        avgKcal: derived.avgKcal7d,
        avgProteinG: derived.avgProtein7d,
        avgRhr: derived.avgRhrBpm,
        avgSleepScore: derived.sleepScore7d,
        acwr: derived.acwr,
        avgKcal7d: derived.avgKcal7d,
        avgProtein7d: derived.avgProtein7d,
        sleepScore7d: derived.sleepScore7d,
        avgWeightKg: derived.avgWeightKg,
        avgRhrBpm: derived.avgRhrBpm,
        avgSteps: derived.avgSteps,
        avgBodyBattery: derived.avgBodyBattery,
        avgKcalBurned7d: derived.avgKcalBurned7d,
        avgKcalGoalRatio: derived.avgKcalGoalRatio,
        proteinPerKg: derived.proteinPerKg,
        avgKcalDeficit7d: derived.avgKcalDeficit7d,
        estWeeklyWeightChangeKg: derived.estWeeklyWeightChangeKg,
        trends: derived.trends ?? .allFlat
    )
}

// MARK: - Rule evaluation

/// `_eval_rule`: evaluate one KPI rule. `nil` means "not applicable" (the
/// metric is missing, or the operator is unknown) — distinct from `false`.
///
/// `metrics` (the raw per-day rows) is required for the count-based rules
/// (`avg_kcal_7d`, `avg_protein_7d`, `sleep_score_7d` with operator `<`); there
/// the rule's `threshold` is the PER-DAY comparison value, not an average.
public nonisolated func evalRule(
    metricName: String,
    operator op: String,
    threshold: Double?,
    thresholdHi: Double?,
    derived: DerivedMetrics,
    metrics: [KpiMetricRow]? = nil,
    config: KpiConfig = defaultKpiConfig
) -> Bool? {
    let thr = threshold

    // Count-based rules — thresholds come from the rule table, not hardcoded.
    if let rule = config.countRuleFields[metricName], op == "<" {
        guard let metrics, !metrics.isEmpty else { return nil }
        var count = 0
        for row in metrics {
            if let v = safeFloat(row[rule.field]), let thr, v < thr { count += 1 }
        }
        return count >= rule.minDays
    }

    // Scalar rules.
    guard let present = derived.value(forMetric: metricName), let val = present else { return nil }

    switch op {
    case ">": return thr.map { val > $0 } ?? false
    case "<": return thr.map { val < $0 } ?? false
    case ">=": return thr.map { val >= $0 } ?? false
    case "<=": return thr.map { val <= $0 } ?? false
    case "between":
        let hi = thresholdHi ?? thr
        guard let thr, let hi else { return false }
        return thr <= val && val <= hi
    default: return nil
    }
}

/// `_build_suggestions`: actionable suggestions for a PROGRESS recommendation.
public nonisolated func buildSuggestions(_ derived: DerivedMetrics,
                                         config: KpiConfig = defaultKpiConfig) -> [String] {
    var suggestions: [String] = []
    let acwr = derived.acwr
    // Mirrors Python's `if acwr and acwr < 1.10` — 0 (and None) are falsy in
    // Python and in the TS oracle, so a 0.0 ACWR deliberately skips this.
    if let acwr, acwr != 0, acwr < 1.10 {
        suggestions.append("Consider increasing training load (ACWR has headroom)")
    }
    suggestions.append("Consider increasing bench press by 2.5 kg")
    return suggestions
}

// MARK: - Verdict-string helpers

/// Python's `str(float)` for a bare `f"{x}"` interpolation: the shortest
/// round-tripping decimal, but ALWAYS with a decimal point.
///
/// Swift's own `Double` description is the same shortest-round-trip algorithm
/// and already prints `1600.0`, `-0.0`, `nan` and `inf` exactly as Python's
/// `repr` does over the health-metric magnitudes this gate deals in; the guard
/// below keeps the "always a decimal point" promise regardless. (Python and
/// Swift diverge only at the exponential-notation cutover for extreme
/// magnitudes, which no KPI threshold or average reaches.)
nonisolated func pythonFloatString(_ x: Double?) -> String {
    guard let x else { return "None" }
    if x.isNaN { return "nan" }
    if x == .infinity { return "inf" }
    if x == -.infinity { return "-inf" }
    if x == 0, x.sign == .minus { return "-0.0" }
    let s = "\(x)"
    return s.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) ? s : s + ".0"
}

/// `derived.get(metric, "?")` — the `"?"` default fires only when the key is
/// entirely ABSENT, not when it is present with a `None` value.
nonisolated func derivedValueForMessage(_ derived: DerivedMetrics, _ metric: String) -> String {
    guard let present = derived.value(forMetric: metric) else { return "?" }
    return pythonFloatString(present)
}

// MARK: - Gate entry points

/// `evaluate_kpi_gates`: run the rule table and return a `GateResult`.
///
/// - Parameters:
///   - metricsRows: per-day metric rows for the caller-selected window. This
///     function does NOT slice to the last 7 days itself.
///   - kpiTargets: rule rows (metric, operator, threshold, thresholdHi,
///     description). The FIRST rule that fires with a REDUCE or MAINTAIN
///     description wins and returns immediately.
public nonisolated func evaluateKpiGates(
    _ metricsRows: [KpiMetricRow],
    _ kpiTargets: [KpiRule],
    config: KpiConfig = defaultKpiConfig
) -> GateResult {
    let derived = computeDerivedMetrics(metricsRows)
    var triggered: [String] = []

    for target in kpiTargets {
        let metric = target.metric
        let op = target.operator
        let threshold = safeFloat(target.threshold)
        let thresholdHi = safeFloat(target.thresholdHi)
        let description = target.description

        let fired = evalRule(metricName: metric, operator: op, threshold: threshold,
                             thresholdHi: thresholdHi, derived: derived,
                             metrics: metricsRows, config: config)

        guard fired == true else { continue }

        let descLower = description.lowercased()
        if descLower.contains("reduce") {
            let val = derivedValueForMessage(derived, metric)
            triggered.append("\(metric) \(val) vs threshold \(pythonFloatString(threshold)) (\(description))")
            return GateResult(recommendation: .reduce, triggeredRules: triggered, suggestions: [])
        } else if descLower.contains("maintain") {
            let val = derivedValueForMessage(derived, metric)
            triggered.append("\(metric) \(val) vs threshold \(pythonFloatString(threshold)) (\(description))")
            return GateResult(recommendation: .maintain, triggeredRules: triggered, suggestions: [])
        } else if descLower.contains("progress") {
            let ratio = derived.avgKcalGoalRatio
            let ppkg = derived.proteinPerKg
            let kcalOk = ratio.map {
                config.progressKcalRatioMin <= $0 && $0 <= config.progressKcalRatioMax
            } ?? false
            let proteinOk = ppkg.map { $0 >= config.progressProteinPerKg } ?? false
            if kcalOk && proteinOk {
                return GateResult(recommendation: .progress, triggeredRules: [],
                                  suggestions: buildSuggestions(derived, config: config))
            }
        }
    }

    // Default: MAINTAIN.
    return GateResult(recommendation: .maintain, triggeredRules: [], suggestions: [])
}

/// `is_tracked_day`: the strict-day definition — enough kcal AND enough meals.
public nonisolated func isTrackedDay(_ row: KpiMetricRow,
                                     config: KpiConfig = defaultKpiConfig) -> Bool {
    // Mirrors Python's `(row.get(...) or 0)`: missing, null and 0 all collapse
    // to 0, and any nonzero value (including a negative one) is kept as-is.
    let kcal = row["kcal_consumed"] ?? 0
    let meals = row["meals_logged"] ?? 0
    return kcal >= config.trackingKcalMin && meals >= config.trackingMealsMin
}

/// `evaluate_gate`: KPI gate + tracking-quality gate — the single decision
/// entry point. The KPI verdict is suppressed with `INSUFFICIENT_DATA` when
/// fewer than `minTrackedDays` of the window were fully tracked, so no consumer
/// can record a recommendation the user was never shown.
public nonisolated func evaluateGate(
    _ metrics: [KpiMetricRow],
    _ kpiTargets: [KpiRule],
    config: KpiConfig = defaultKpiConfig
) -> GateDecision {
    let trackedDays = metrics.reduce(into: 0) { $0 += isTrackedDay($1, config: config) ? 1 : 0 }
    let totalDays = metrics.count

    if trackedDays < config.minTrackedDays {
        return GateDecision(recommendation: .insufficientData, triggeredRules: [],
                            suggestions: [], trackedDays: trackedDays, totalDays: totalDays)
    }

    let gate = evaluateKpiGates(metrics, kpiTargets, config: config)
    return GateDecision(recommendation: GateDecisionRecommendation(gate.recommendation),
                        triggeredRules: gate.triggeredRules, suggestions: gate.suggestions,
                        trackedDays: trackedDays, totalDays: totalDays)
}

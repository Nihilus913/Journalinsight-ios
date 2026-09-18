import Foundation

// MARK: - Rows and rules

/// A single day's raw metric row (a `core.*` join, as loaded for the gate).
///
/// The keys stay snake_case on purpose: the rule table is DATA — a
/// `plan.kpi_target` row carries a `metric` string (e.g. `"avg_kcal_7d"`) and
/// `COUNT_RULE_FIELDS` maps that to a per-day row field name (e.g.
/// `"kcal_consumed"`). Both are looked up dynamically at runtime, exactly as
/// Python's `row.get(field)` and the TS oracle's index signature do, so the
/// golden fixtures pass straight through with no case-mapping layer.
public struct KpiMetricRow: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    /// Present-with-nil (JSON `null`) and absent are both read as "no value",
    /// matching Python's `dict.get`.
    public var values: [String: Double?]

    public init(_ values: [String: Double?] = [:]) { self.values = values }

    public init(dictionaryLiteral elements: (String, Double?)...) {
        var v: [String: Double?] = [:]
        for (k, value) in elements { v.updateValue(value, forKey: k) }
        self.values = v
    }

    /// `row.get(key)` — absent and explicit null collapse to `nil`.
    public subscript(key: String) -> Double? { values[key] ?? nil }

    public static func == (lhs: KpiMetricRow, rhs: KpiMetricRow) -> Bool {
        guard lhs.values.count == rhs.values.count else { return false }
        for (k, v) in lhs.values {
            guard let other = rhs.values[k], other == v else { return false }
        }
        return true
    }
}

/// A single row of `plan.kpi_target` — the rule table is DATA, not code.
public struct KpiRule: Sendable, Equatable {
    public var metric: String
    public var `operator`: String  // ">" | "<" | ">=" | "<=" | "between"
    public var threshold: Double?
    public var thresholdHi: Double?
    public var description: String

    public init(metric: String, operator op: String, threshold: Double?,
                thresholdHi: Double? = nil, description: String = "") {
        self.metric = metric
        self.operator = op
        self.threshold = threshold
        self.thresholdHi = thresholdHi
        self.description = description
    }
}

// MARK: - Trends

public enum TrendDirection: String, Sendable, Equatable {
    case up, down, flat
}

public struct TrendMap: Sendable, Equatable {
    public var kcal: TrendDirection
    public var protein: TrendDirection
    public var rhr: TrendDirection
    public var sleep: TrendDirection
    public var acwr: TrendDirection
    public var bodyBattery: TrendDirection
    public var kcalBurned: TrendDirection

    public init(kcal: TrendDirection, protein: TrendDirection, rhr: TrendDirection,
                sleep: TrendDirection, acwr: TrendDirection, bodyBattery: TrendDirection,
                kcalBurned: TrendDirection) {
        self.kcal = kcal
        self.protein = protein
        self.rhr = rhr
        self.sleep = sleep
        self.acwr = acwr
        self.bodyBattery = bodyBattery
        self.kcalBurned = kcalBurned
    }

    /// The `_empty` skeleton `compute_averages` merges under its derived dict.
    public static let allFlat = TrendMap(kcal: .flat, protein: .flat, rhr: .flat, sleep: .flat,
                                         acwr: .flat, bodyBattery: .flat, kcalBurned: .flat)
}

// MARK: - Derived metrics

/// Mirrors `_compute_derived_metrics`'s return dict.
///
/// Python returns a bare `{}` — no keys at all — for an empty input list, and
/// that is observable: `evaluate_kpi_gates` formats `derived.get(metric, "?")`,
/// whose default fires only when the KEY IS ABSENT (not when it is present with
/// a `None` value). `isEmpty` carries that distinction; `value(forMetric:)`
/// returns a double optional so callers can tell absent from present-but-nil.
public struct DerivedMetrics: Sendable, Equatable {
    /// `true` == Python's bare `{}` (no keys at all), not "every value is nil".
    public var isEmpty: Bool
    public var acwr: Double?
    public var avgKcal7d: Double?
    public var avgProtein7d: Double?
    public var sleepScore7d: Double?
    public var avgWeightKg: Double?
    public var avgRhrBpm: Double?
    public var avgSteps: Double?
    public var avgBodyBattery: Double?
    public var avgKcalBurned7d: Double?
    public var avgKcalGoalRatio: Double?
    public var proteinPerKg: Double?
    public var avgKcalDeficit7d: Double?
    public var estWeeklyWeightChangeKg: Double?
    /// `nil` only when `isEmpty` — the key is absent in that case.
    public var trends: TrendMap?

    public init(isEmpty: Bool = false, acwr: Double? = nil, avgKcal7d: Double? = nil,
                avgProtein7d: Double? = nil, sleepScore7d: Double? = nil,
                avgWeightKg: Double? = nil, avgRhrBpm: Double? = nil, avgSteps: Double? = nil,
                avgBodyBattery: Double? = nil, avgKcalBurned7d: Double? = nil,
                avgKcalGoalRatio: Double? = nil, proteinPerKg: Double? = nil,
                avgKcalDeficit7d: Double? = nil, estWeeklyWeightChangeKg: Double? = nil,
                trends: TrendMap? = nil) {
        self.isEmpty = isEmpty
        self.acwr = acwr
        self.avgKcal7d = avgKcal7d
        self.avgProtein7d = avgProtein7d
        self.sleepScore7d = sleepScore7d
        self.avgWeightKg = avgWeightKg
        self.avgRhrBpm = avgRhrBpm
        self.avgSteps = avgSteps
        self.avgBodyBattery = avgBodyBattery
        self.avgKcalBurned7d = avgKcalBurned7d
        self.avgKcalGoalRatio = avgKcalGoalRatio
        self.proteinPerKg = proteinPerKg
        self.avgKcalDeficit7d = avgKcalDeficit7d
        self.estWeeklyWeightChangeKg = estWeeklyWeightChangeKg
        self.trends = trends
    }

    /// Python's bare `return {}`.
    public static let empty = DerivedMetrics(isEmpty: true)

    /// `derived.get(name)` for the scalar (non-`trends`) keys.
    ///
    /// Outer `nil` = the key is absent (empty dict, or a metric name the rule
    /// table invented); inner `nil` = present with a `None` value. `"trends"`
    /// is reported absent on purpose: its value is a dict, so the scalar
    /// comparisons below would raise in Python and the TS oracle's
    /// `typeof val !== "number"` guard already returns `null` for it.
    public func value(forMetric name: String) -> Double?? {
        if isEmpty { return nil }
        switch name {
        case "acwr": return .some(acwr)
        case "avg_kcal_7d": return .some(avgKcal7d)
        case "avg_protein_7d": return .some(avgProtein7d)
        case "sleep_score_7d": return .some(sleepScore7d)
        case "avg_weight_kg": return .some(avgWeightKg)
        case "avg_rhr_bpm": return .some(avgRhrBpm)
        case "avg_steps": return .some(avgSteps)
        case "avg_body_battery": return .some(avgBodyBattery)
        case "avg_kcal_burned_7d": return .some(avgKcalBurned7d)
        case "avg_kcal_goal_ratio": return .some(avgKcalGoalRatio)
        case "protein_per_kg": return .some(proteinPerKg)
        case "avg_kcal_deficit_7d": return .some(avgKcalDeficit7d)
        case "est_weekly_weight_change_kg": return .some(estWeeklyWeightChangeKg)
        default: return nil
        }
    }
}

/// `compute_averages`'s return dict: every `DerivedMetrics` key (always
/// present, nil when there is no data) plus the four convenience aliases.
public struct AveragesResult: Sendable, Equatable {
    public var avgKcal: Double?
    public var avgProteinG: Double?
    public var avgRhr: Double?
    public var avgSleepScore: Double?
    public var acwr: Double?
    public var avgKcal7d: Double?
    public var avgProtein7d: Double?
    public var sleepScore7d: Double?
    public var avgWeightKg: Double?
    public var avgRhrBpm: Double?
    public var avgSteps: Double?
    public var avgBodyBattery: Double?
    public var avgKcalBurned7d: Double?
    public var avgKcalGoalRatio: Double?
    public var proteinPerKg: Double?
    public var avgKcalDeficit7d: Double?
    public var estWeeklyWeightChangeKg: Double?
    public var trends: TrendMap
}

// MARK: - Verdicts

/// 1:1 with `JICore.GateRecommendation`'s first three cases — same raw values,
/// so the eventual consumer maps without a translation table. JICompute cannot
/// import JICore (the package depends on Foundation only, by design), hence the
/// mirrored declaration rather than a re-export.
public enum GateRecommendation: String, Sendable, Equatable {
    case progress = "PROGRESS"
    case maintain = "MAINTAIN"
    case reduce = "REDUCE"
}

/// 1:1 with `JICore.GateRecommendation` (all four cases).
public enum GateDecisionRecommendation: String, Sendable, Equatable {
    case progress = "PROGRESS"
    case maintain = "MAINTAIN"
    case reduce = "REDUCE"
    case insufficientData = "INSUFFICIENT_DATA"

    public init(_ recommendation: GateRecommendation) {
        switch recommendation {
        case .progress: self = .progress
        case .maintain: self = .maintain
        case .reduce: self = .reduce
        }
    }
}

/// Mirrors `app/planning/models.py::GateResult`.
public struct GateResult: Sendable, Equatable {
    public var recommendation: GateRecommendation
    public var triggeredRules: [String]
    public var suggestions: [String]

    public init(recommendation: GateRecommendation, triggeredRules: [String] = [],
                suggestions: [String] = []) {
        self.recommendation = recommendation
        self.triggeredRules = triggeredRules
        self.suggestions = suggestions
    }
}

/// Mirrors `app/planning/models.py::GateDecision`.
public struct GateDecision: Sendable, Equatable {
    public var recommendation: GateDecisionRecommendation
    public var triggeredRules: [String]
    public var suggestions: [String]
    public var trackedDays: Int
    public var totalDays: Int

    public init(recommendation: GateDecisionRecommendation, triggeredRules: [String] = [],
                suggestions: [String] = [], trackedDays: Int = 0, totalDays: Int = 0) {
        self.recommendation = recommendation
        self.triggeredRules = triggeredRules
        self.suggestions = suggestions
        self.trackedDays = trackedDays
        self.totalDays = totalDays
    }
}

// MARK: - Config

/// Every threshold/coefficient `app/planning/service.py` hard-codes at module
/// scope.
public struct KpiConfig: Sendable, Equatable {
    /// `>=` this fraction of `kcal_goal` counts toward PROGRESS.
    public var progressKcalRatioMin: Double
    /// `<=` this fraction of `kcal_goal` counts toward PROGRESS.
    public var progressKcalRatioMax: Double
    /// g protein per kg body weight required for PROGRESS.
    public var progressProteinPerKg: Double
    /// Minimum kcal logged for a day to count as tracked (strict-day rule).
    public var trackingKcalMin: Double
    /// Minimum meals logged for a day to count as tracked.
    public var trackingMealsMin: Double
    /// Below this many tracked days in the window, `evaluateGate` returns
    /// `INSUFFICIENT_DATA`.
    public var minTrackedDays: Int
    /// metric name -> (per-day row field, minimum day count) for the count-based
    /// "N of 7 days below threshold" rules.
    public var countRuleFields: [String: (field: String, minDays: Int)]

    public init(progressKcalRatioMin: Double, progressKcalRatioMax: Double,
                progressProteinPerKg: Double, trackingKcalMin: Double,
                trackingMealsMin: Double, minTrackedDays: Int,
                countRuleFields: [String: (field: String, minDays: Int)]) {
        self.progressKcalRatioMin = progressKcalRatioMin
        self.progressKcalRatioMax = progressKcalRatioMax
        self.progressProteinPerKg = progressProteinPerKg
        self.trackingKcalMin = trackingKcalMin
        self.trackingMealsMin = trackingMealsMin
        self.minTrackedDays = minTrackedDays
        self.countRuleFields = countRuleFields
    }

    public static func == (lhs: KpiConfig, rhs: KpiConfig) -> Bool {
        lhs.progressKcalRatioMin == rhs.progressKcalRatioMin
            && lhs.progressKcalRatioMax == rhs.progressKcalRatioMax
            && lhs.progressProteinPerKg == rhs.progressProteinPerKg
            && lhs.trackingKcalMin == rhs.trackingKcalMin
            && lhs.trackingMealsMin == rhs.trackingMealsMin
            && lhs.minTrackedDays == rhs.minTrackedDays
            && lhs.countRuleFields.count == rhs.countRuleFields.count
            && lhs.countRuleFields.allSatisfy { key, value in
                rhs.countRuleFields[key].map { $0 == value } ?? false
            }
    }
}

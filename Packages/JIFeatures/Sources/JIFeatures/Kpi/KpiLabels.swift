import Foundation
import JICore
import JICompute
import JIDesign

// W-B34 L1: the KPI registry moved to `JICore/Kpi/KpiMetrics.swift`; these two screen-copy helpers
// stay in JIFeatures (`kpiAsOfLabel` uses JIFeatures' `trainingStripDate`).

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
    case "<", "<=": return "Tell me when \(metricLabel) falls below"
    case ">", ">=": return "Tell me when \(metricLabel) rises above"
    case "between": return "Tell me when \(metricLabel) leaves the range starting at"
    default: return "Alert threshold for \(metricLabel)"
    }
}

/// B-57 W1 board subtitle under the KPI detail title: where the number comes from. Device-neutral
/// ("your watch") for the recovery signals — the gate is source-agnostic — and the board's own
/// wording for the macros.
public nonisolated func kpiSourceSubtitle(_ id: KpiMetricId) -> String {
    switch id {
    case .hrv, .rhr: "Your watch · measured while you sleep"
    case .sleep: "Your watch · scored each night"
    case .bodyBattery, .readiness: "Your watch · each morning"
    case .acwr: "Worked out from your training sessions"
    case .weight: "Your weigh-ins"
    case .steps: "Your watch or phone"
    case .kcal, .protein, .carbs, .fat: "Read from Apple Health · written by YAZIO"
    }
}

/// One tap of the alert stepper, in the metric's own precision (ACWR moves in 0.05s).
public nonisolated func kpiAlertStep(decimals: Int) -> Double {
    switch decimals {
    case ...0: 1
    case 1: 0.1
    default: 0.05
    }
}

// MARK: - W-FIX5 L1 (WD-1): the gate-input Load on the KPI detail

/// What the KPI detail shows for its metric: the registry entry (`KpiMetricDef`), or — WD-1 — the
/// Load in minutes. Same member names as `KpiMetricDef`, so the screen reads `model.def.label`.
public nonisolated struct KpiDetailDef: Sendable, Equatable {
    public let id: KpiMetricId
    public let label: String
    public let unit: String
    public let decimals: Int
    public let maxLiveWindowDays: Int
    public let targetMetricKeys: [String]
    public init(_ d: KpiMetricDef) {
        self.init(id: d.id, label: d.label, unit: d.unit, decimals: d.decimals, maxLiveWindowDays: d.maxLiveWindowDays,
                  targetMetricKeys: d.targetMetricKeys)
    }
    public init(id: KpiMetricId, label: String, unit: String, decimals: Int, maxLiveWindowDays: Int, targetMetricKeys: [String]) {
        self.id = id; self.label = label; self.unit = unit; self.decimals = decimals
        self.maxLiveWindowDays = maxLiveWindowDays; self.targetMetricKeys = targetMetricKeys
    }
}

/// The Load detail's definition while no current ACWR exists: the same 7-day minutes the Today /
/// Recovery Load square shows (`RecoveryLoadReading`), whole minutes, and no gate rule (the ACWR
/// rules are ratios — their editor never edits minutes).
public nonisolated let kpiLoadMinutesDef = KpiDetailDef(id: .acwr, label: "Training load", unit: recoveryLoadUnit, decimals: 0,
                                                        maxLiveWindowDays: 365, targetMetricKeys: [])

/// The Load detail's series: for each day D the 7-day load ending D (`RecoveryScore.load7`, the
/// number the Load square and the recovery score use), from the first full week through
/// yesterday. A week with too few logged days is nil (a gap), never 0.
public nonisolated func kpiLoadHistory(days: [RecoveryInputDay], today: String) -> [(date: String, value: Double?)] {
    guard !today.isEmpty else { return [] }
    var daily: [String: Double] = [:]
    for d in days { if let v = d.loadMin, v.isFinite, v >= 0 { daily[d.date] = v } }
    guard let first = daily.keys.min(),
          var d = try? CalendarMath.addDays(first, 6),
          let yesterday = try? CalendarMath.addDays(today, -1) else { return [] }
    var out: [(date: String, value: Double?)] = []
    while d <= yesterday {
        out.append((d, (try? RecoveryScore.load7(daily, end: d)) ?? nil))
        guard let next = try? CalendarMath.addDays(d, 1) else { break }
        d = next
    }
    return out
}

// MARK: - W-FIX10 R-04: the hub's calibration block (HT DH-4)

/// The hub's calibration component a KPI's normal is built on; nil for any other metric.
public nonisolated func kpiCalibrationKey(_ metric: KpiMetricId) -> String? {
    switch metric {
    case .hrv: "hrv"
    case .rhr: "rhr"
    default: nil
    }
}

/// "Calibrating · 4 of 14 nights" when the hub says `key`'s normal is still calibrating, else nil
/// (then the phone's own band stands). Never a band built on too few real nights (rule 5).
public nonisolated func recoveryCalibrationCaption(_ calibration: RecoveryCalibration?, key: String) -> String? {
    guard let calibration, calibration.isCalibrating(key) else { return nil }
    let need = key == "load" ? RecoveryScore.loadMinNormalN : calibration.nightsNeeded
    let n = max(0, min(calibration.component(key)?.nights ?? calibration.nights, need))
    return "\(JIMissingReason.calibrating.rawValue) · \(n) of \(need) nights"
}

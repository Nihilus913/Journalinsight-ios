import Foundation
import JICore

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

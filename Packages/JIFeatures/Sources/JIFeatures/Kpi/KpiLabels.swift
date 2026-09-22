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
    case "<", "<=": return "Alert when \(metricLabel) falls below"
    case ">", ">=": return "Alert when \(metricLabel) rises above"
    case "between": return "Alert when \(metricLabel) leaves the range starting at"
    default: return "Alert threshold for \(metricLabel)"
    }
}

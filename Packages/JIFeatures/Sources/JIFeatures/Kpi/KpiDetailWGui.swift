import Foundation
import JICore
import JICompute
import JIDesign

// W-GUI R2 — KPI detail (mockups 07 / 20 / 21): the table under the chart, the per-metric block
// and the clinician caption, all pure. Nothing here invents a number: a missing slot is "—" + why.

/// One row of the table under the chart: title, the one-line meaning, the value slot.
public nonisolated struct KpiDetailTableRow: Equatable, Sendable, Identifiable {
    public let id: String, title: String, subtitle: String, value: String
}

/// Last night · 7-day average · 28-day normal (W3 → "—") · Nights counted. W-FIX6 F6-3: the words
/// say what the number is — the mean of the last 7, never "the number the gate uses" (the gate
/// reads last night, and Load is not in the call), and the band is median ± spread, not a middle 50 %.
public nonisolated func kpiDetailTableRows(history: [(date: String, value: Double?)], value: Double?, unit: String, decimals: Int,
                                           isNightly: Bool = true, normal: PersonalNormalResult? = nil) -> [KpiDetailTableRow] {
    let u = unit.isEmpty ? "" : " \(unit)"
    func num(_ v: Double?) -> String { v.map { kpiDetailNumber($0, decimals: decimals) + u } ?? "—" }
    let sorted = history.sorted { $0.date < $1.date }
    let last28 = sorted.suffix(28)
    let counted = last28.filter { $0.value != nil }.count
    let avg7 = trendAverage(history, days: 7)
    // Load's series is the rolling 7-day total (`kpiLoadHistory`): its words name weekly totals.
    let isLoad = unit == recoveryLoadUnit
    let lastSubtitle = isLoad ? "total of the 7 days to yesterday" : isNightly ? "the newest night" : "the newest reading"
    let avgSubtitle = isLoad ? "mean of the last 7 weekly totals" : isNightly ? "mean of the last 7 nights" : "mean of the last 7 days"
    let normalSubtitle = isLoad ? "median ± usual spread of weekly totals, 4 weeks before this week"
                                : "median ± usual spread, 4 weeks before this week"
    return [
        KpiDetailTableRow(id: "last", title: isNightly ? "Last night" : "Latest", subtitle: lastSubtitle, value: num(value)),
        KpiDetailTableRow(id: "avg7", title: "7-day average", subtitle: avgSubtitle, value: num(avg7)),
        KpiDetailTableRow(id: "normal", title: "28-day normal", subtitle: normalSubtitle, value: normal.map { "\(kpiDetailNumber($0.low, decimals: decimals))–\(kpiDetailNumber($0.high, decimals: decimals))\(u)" } ?? "— \(JIMissingReason.calibrating.rawValue)"),
        KpiDetailTableRow(id: "counted", title: isNightly ? "Nights counted" : "Days counted", subtitle: "missing ones stay missing", value: "\(counted) of \(max(last28.count, 1))"),
    ]
}

/// The chart legend: honest until W3 lands the band.
public nonisolated let kpiDetailLegend = "shaded = your normal — \(JIMissingReason.calibrating.rawValue) · dashed = median —"

/// W-B57-W3 fixer: the legend with the band once `KpiNormal` has one (the same band the NormalBar shows).
public nonisolated func kpiDetailLegendText(_ normal: PersonalNormalResult?, decimals: Int) -> String {
    guard let normal else { return kpiDetailLegend }
    return "shaded = your normal \(kpiDetailNumber(normal.low, decimals: decimals))–\(kpiDetailNumber(normal.high, decimals: decimals)) · dashed = median \(kpiDetailNumber(normal.median, decimals: decimals))"
}

/// The per-metric block under the table (a section title, rows with a trailing value, a caption).
public nonisolated struct KpiDetailBlock: Equatable, Sendable {
    public let title: String
    public let rows: [(title: String, subtitle: String, value: String)]
    public let caption: String
    public static func == (a: KpiDetailBlock, b: KpiDetailBlock) -> Bool {
        a.title == b.title && a.caption == b.caption && a.rows.map(\.title) == b.rows.map(\.title) && a.rows.map(\.value) == b.rows.map(\.value)
    }
}

/// HRV (07): "Same wrist, two numbers" — RMSSD vs SDNN (SDNN row "— not read yet", plan §B).
/// RHR (20): "Not used" — daytime heart rate is context only. Sleep (21): "How the score is
/// built" with the convention caption; components "— not read" until Health carries them.
/// W-FIX5 fixer: `deepRem` = last night's deep + REM (`kpiDetailDeepRemText`); `sdnn` = the gate's
/// daytime HRV (Apple's SDNN, context only). nil = "— not read" (never invented).
/// W-B67 R-3 fixer: `scoreBreakdownShown` = the hub's "How this score is built" section is on screen;
/// the Sleep convention block is then nil — one explanation of the score per screen, never two.
public nonisolated func kpiDetailBlock(metric: KpiMetricId, valueText: String?, sleepDuration: String?,
                                       deepRem: String? = nil, sdnn: String? = nil,
                                       scoreBreakdownShown: Bool = false) -> KpiDetailBlock? {
    switch metric {
    case .hrv:
        return KpiDetailBlock(title: "Same wrist, two numbers", rows: [
            ("JI · Overnight HRV (RMSSD)", "beat-to-beat, sleep only · used by the morning call", valueText ?? "—"),
            ("Health app · HRV (SDNN)", "whole-window spread, daytime samples · not used", sdnn ?? "— not read yet"),
            ("Daytime HRV", "shown for context only", sdnn ?? "—"),
        ], caption: "A 30 ms SDNN and a 30 ms RMSSD are not the same thing. JI compares each metric only with its own history. HRV is a training signal here, not a medical reading.")
    case .rhr:
        return KpiDetailBlock(title: "Not used", rows: [
            ("Daytime heart rate", "context only · not part of the call", "—"),
        ], caption: "A drift over weeks is worth a look with your clinician; a single night is not. JI does not interpret heart rhythm.")
    case .sleep:
        if scoreBreakdownShown { return nil }
        return KpiDetailBlock(title: "How the score is built", rows: [
            ("Duration", "of your goal · 50 %", sleepDuration ?? "— not read"),
            ("Deep + REM", "20 %", deepRem ?? "— not read"),
            ("Consistency", "vs your usual bedtime · 20 %", "— not read"),
            ("Awake", "10 %", "— not read"),
        ], caption: "Weights are a convention, not evidence; the score exists so one number can sit under the call. The night itself is what Health recorded.")
    default:
        return nil
    }
}

/// W-FIX5 fixer (KPI-sleep-block): last night's deep + REM from the recovery rows — the newest night
/// that carries BOTH stages, and only when it is last night (the ≤ 36 h rule Recovery's Deep tile
/// uses); nil otherwise.
public nonisolated func kpiDetailDeepRemText(days: [RecoveryDay], now: Date) -> String? {
    guard let d = days.sorted(by: { $0.date > $1.date }).first(where: { $0.deepSleepSec != nil || $0.remSleepSec != nil }),
          let deep = d.deepSleepSec, let rem = d.remSleepSec,
          KpiMetrics.isLastNightFresh(nightDate: d.date, now: now) else { return nil }
    return recoverySleepDuration(seconds: deep + rem)
}

/// The screen's subtitle (mockups 07 / 20 / 21) per metric.
public nonisolated func kpiDetailSubtitle(_ metric: KpiMetricId) -> String {
    switch metric {
    case .hrv: "RMSSD · Apple Watch · while asleep"
    case .rhr: "Overnight · Apple Watch · while asleep"
    case .sleep: "Apple Watch · hub score"
    default: kpiSourceSubtitle(metric)
    }
}

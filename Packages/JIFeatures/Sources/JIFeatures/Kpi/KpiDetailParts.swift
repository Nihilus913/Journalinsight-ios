import SwiftUI
import Charts
import JICore
import JIDesign

// B-57 W1 fixer: the KpiDetail board's pieces (`2 Monitor/03 KpiDetail.png`), shared by the
// shipped `KpiDetailView` and the "KPI detail" registry preview so the two cannot drift.

/// The board's 7 D / 30 D / 90 D range picker (not Health's D/W/M/6M/Y).
public nonisolated enum KpiDetailRange: Int, CaseIterable, Sendable, Identifiable {
    case week = 7, month = 30, quarter = 90
    public var id: Int { rawValue }
    public var days: Int { rawValue }
    public var label: String { "\(rawValue) D" }
}

/// The newest `range.days` calendar days of the history, ending at its newest day. A day with no
/// reading is left out — never plotted as a zero (rule 5).
public nonisolated func kpiDetailTrendPoints(_ history: [(date: String, value: Double?)], range: KpiDetailRange) -> [TrendPoint] {
    guard let newest = history.compactMap({ trainingStripDate($0.date) }).max(),
          let cutoff = trainingStripCalendar.date(byAdding: .day, value: -(range.days - 1), to: newest) else { return [] }
    return history
        .compactMap { point -> TrendPoint? in
            guard let value = point.value, let date = trainingStripDate(point.date), date >= cutoff else { return nil }
            return TrendPoint(date: date, value: value)
        }
        .sorted { $0.date < $1.date }
}

/// Range picker over a line chart with a trailing axis. Empty = "No data yet" (rule 5).
struct KpiDetailTrend: View {
    let points: [TrendPoint]
    let label: String
    let unit: String?
    @Binding var range: KpiDetailRange
    private let theme = JITheme.native
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(KpiDetailRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("kpi-detail-range")
            Surface {
                Chart(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                        .foregroundStyle(theme.color(.info))
                        .interpolationMethod(.monotone)
                    if points.count == 1 {
                        PointMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value)).foregroundStyle(theme.color(.info))
                    }
                }
                .chartYAxis { AxisMarks(position: .trailing) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 2 : 4)) }
                .frame(minHeight: chartHeight)
                .overlay {
                    if points.isEmpty { Text("No data yet").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                }
                .accessibilityLabel("\(label) trend")
                .accessibilityIdentifier("kpi-detail-chart")
            }
        }
    }
}

/// The board's alert row: the rule in words ("Tell me when HRV falls below"), the threshold with
/// its unit, a − / + stepper, and a full-width "Save alert".
struct KpiAlertEditor: View {
    let sentence: String
    @Binding var value: Double
    let unit: String
    let decimals: Int
    let saving: Bool
    let dirty: Bool
    let error: String?
    let onSave: () -> Void
    private let theme = JITheme.native
    @Environment(\.dynamicTypeSize) private var typeSize

    private var step: Double { kpiAlertStep(decimals: decimals) }
    private var shownDecimals: Int { decimals >= 2 ? 2 : decimals }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JISectionHeader("Alert")
            Surface {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    Text(sentence).jiFont(.body).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("kpi-detail-threshold-label")
                    HStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatKpiValue(value, decimals: shownDecimals)).jiNumeral(.numeralSmall)
                                .foregroundStyle(theme.color(.text)).monospacedDigit()
                                .accessibilityIdentifier("kpi-detail-threshold-value")
                            if !unit.isEmpty { Text(unit).jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                        }
                        stepper
                    }
                    .fixedSize()
                }
            }
            Button(action: onSave) {
                Text(saving ? "Saving…" : "Save alert").jiFont(.body, weight: .semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(theme.color(.info))
            .disabled(saving || !dirty)
            .accessibilityIdentifier("kpi-detail-threshold-save")
            if let error {
                Text(error).jiFont(.footnote).foregroundStyle(theme.color(.reduced))
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Lower the threshold", delta: -step)
            Divider().frame(height: 18)
            stepButton("plus", label: "Raise the threshold", delta: step)
        }
        .background(theme.color(.control), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Threshold")
        .accessibilityValue(formatKpiValue(value, decimals: shownDecimals) + (unit.isEmpty ? "" : " \(unit)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = kpiAlertStepped(value, by: step)
            case .decrement: value = kpiAlertStepped(value, by: -step)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("kpi-detail-threshold-stepper")
    }

    private func stepButton(_ symbol: String, label: String, delta: Double) -> some View {
        Button { value = kpiAlertStepped(value, by: delta) } label: {
            Image(systemName: symbol).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One stepper tap, snapped to the step's grid so 0.05s never drift into 1.0999999.
public nonisolated func kpiAlertStepped(_ value: Double, by delta: Double) -> Double {
    let step = abs(delta)
    guard step > 0 else { return value }
    return max(0, ((value + delta) / step).rounded() * step)
}

/// The board's line under the title: where the number comes from, with the "Last synced" pill
/// beside it on the nutrition detail (below it when the line needs the width).
struct KpiDetailSourceLine: View {
    let subtitle: String
    let fetchedAt: Date?
    let showsSynced: Bool
    private let theme = JITheme.native

    var body: some View {
        let text = Text(subtitle).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("kpi-detail-source")
        if showsSynced {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) { text.fixedSize(); Spacer(minLength: 4); SyncedPill(date: fetchedAt, label: .lastSynced) }
                VStack(alignment: .leading, spacing: 8) { text; SyncedPill(date: fetchedAt, label: .lastSynced) }
            }
        } else {
            text.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - B-57 W1 r4: the value card's status word and explanation line

/// The board's value card carries a status word and one line of explanation. The personal normal
/// band is W3, so W1's honest baseline is the metric's own 28-day average (the same one Trends
/// reads against): the last reading is Up / Down / Steady against it — a direction, never a
/// judgement (for resting HR down is good, for HRV up is).
public nonisolated struct KpiDetailStatus: Equatable, Sendable {
    public let word: String
    public let symbolName: String
    public let detail: String
    public let role: JIColorRole
}

/// Readings the 28-day average needs before a direction means anything.
public nonisolated let kpiDetailMinBaselineReadings = 7

public nonisolated func kpiDetailStatus(history: [(date: String, value: Double?)], value: Double?,
                                        unit: String, decimals: Int) -> KpiDetailStatus {
    guard let value, value.isFinite else {
        return KpiDetailStatus(word: "— \(JIMissingReason.noData.rawValue)", symbolName: "minus",
                               detail: "Nothing from this source yet.", role: .muted)
    }
    let window = history.sorted { $0.date < $1.date }.suffix(trendBaselineDays).compactMap(\.value)
    guard window.count >= kpiDetailMinBaselineReadings, let baseline = trendAverage(history, days: trendBaselineDays) else {
        return KpiDetailStatus(word: "— \(JIMissingReason.calibrating.rawValue)", symbolName: "minus",
                               detail: "JI compares against your 28-day average once it has \(kpiDetailMinBaselineReadings) readings (\(window.count) so far).",
                               role: .muted)
    }
    let direction = trendDirection(recent: value, baseline: baseline)
    let word = switch direction { case .up: "Up"; case .down: "Down"; case .flat: "Steady"; case .unknown: "—" }
    let avg = jiNumber(baseline, decimals) + (unit.isEmpty ? "" : " \(unit)")
    return KpiDetailStatus(word: word, symbolName: direction.symbolName,
                           detail: "Your last reading against your 28-day average of \(avg).", role: .text)
}

/// The value card: the number, its status word and the explanation line (board `03 KpiDetail`).
struct KpiDetailValueCard: View {
    let valueText: String
    let label: String
    let status: KpiDetailStatus
    let asOf: String?
    private let theme = JITheme.native

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 4) {
                Text(valueText)
                    .jiNumeral(.numeralLarge).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(label)
                    .accessibilityValue(valueText)
                    .accessibilityIdentifier("kpi-detail-value")
                Group {
                    // "— Calibrating" / "— No data" already lead with the dash: no second glyph.
                    if status.word.hasPrefix("—") { Text(status.word) } else { Label(status.word, systemImage: status.symbolName) }
                }
                .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(status.role))
                .accessibilityIdentifier("kpi-detail-status")
                Text(status.detail).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kpi-detail-status-detail")
                // B-46 item 3: a fallback reading is labelled with the day it came from, so an
                // older number is never presented as today's.
                if let asOf {
                    Text(asOf).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("kpi-detail-as-of")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

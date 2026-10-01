import SwiftUI
import Charts
import JICore
import JICompute
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
    /// W-GUI R2: the line wears the metric's colour, never the accent (rule 6).
    var tint: JIColorRole = .text
    /// W-B57-W3 fixer: the legend's words (`kpiDetailLegendText`); the calibrating legend by default.
    var legend: String = kpiDetailLegend
    /// W-FIX5 fixer (KPI-legend): the band + median the legend names, drawn under the line (the
    /// same `KpiNormal` band the NormalBar shows). nil = no band yet, and the legend says so.
    var normal: PersonalNormalResult? = nil
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
                VStack(alignment: .leading, spacing: 8) {
                Chart {
                    // "shaded = your normal": the 28-day band across the plot, under the line.
                    if let normal, !points.isEmpty {
                        RectangleMark(yStart: .value("Normal low", normal.low), yEnd: .value("Normal high", normal.high))
                            .foregroundStyle(theme.color(tint).opacity(0.14))
                            .accessibilityLabel("Your normal")
                            .accessibilityValue("\(jiNumber(normal.low, 1)) to \(jiNumber(normal.high, 1))")
                        // "dashed = median".
                        RuleMark(y: .value("Median", normal.median))
                            .foregroundStyle(theme.color(tint).opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .accessibilityLabel("Median")
                    }
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                            .foregroundStyle(theme.color(tint))
                            .interpolationMethod(.monotone)
                        if points.count == 1 {
                            PointMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value)).foregroundStyle(theme.color(tint))
                        }
                    }
                }
                .chartYAxis {
                    // W-FIX11 H1-16: the axis groups like every other number here ("20,000").
                    AxisMarks(position: .trailing) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let d = v.as(Double.self) { Text(verbatim: kpiAxisNumber(d)) } }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: typeSize.isAccessibilitySize ? 2 : 4)) }
                .frame(minHeight: chartHeight)
                .overlay {
                    if points.isEmpty { Text("No data yet").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                }
                .accessibilityLabel("\(label) trend")
                .accessibilityIdentifier("kpi-detail-chart")
                // W-GUI R2 (mockup 07): the legend is honest until W3 lands the band.
                Text(legend).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                }
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

/// W-FIX11 H2-04: the source-labelled metrics (HRV / RHR / Sleep say "Apple Watch") read only the
/// nights that source has for the metric — `sourceDays` = the hub's Apple-only
/// `/vitals/recovery-inputs` days. A night without an Apple value stays in the series as missing
/// (never a Garmin number in an "Apple Watch" average). No source days (an older hub, a mock, any
/// other metric) = the history as is.
public nonisolated func kpiSourceFilteredHistory(_ history: [(date: String, value: Double?)], metric: KpiMetricId,
                                                 sourceDays: [RecoveryInputDay]) -> [(date: String, value: Double?)] {
    guard !sourceDays.isEmpty, let field = kpiSourceField(metric) else { return history }
    let nights = Set(sourceDays.filter { field($0) != nil }.map(\.date))
    return history.map { (date: $0.date, value: nights.contains($0.date) ? $0.value : nil) }
}

/// The Apple input that marks a night as the labelled source's for `metric` (nil = not filtered).
nonisolated func kpiSourceField(_ metric: KpiMetricId) -> ((RecoveryInputDay) -> Double?)? {
    switch metric {
    case .hrv: { $0.hrvMs }
    case .rhr: { $0.rhrBpm }
    case .sleep: { $0.sleepH }
    default: nil
    }
}

/// Readings the 28-day average needs before a direction means anything. W-FIX11 H2-09: 14, the
/// hub's own calibration count (7 said "Steady" beside "Calibrating · 6 of 14 nights").
public nonisolated let kpiDetailMinBaselineReadings = 14

/// W-FIX11 H2-09: a reading older than this many days gets no direction word.
public nonisolated let kpiDetailFreshDays = 2

/// `hubCalibrating`: the hub says this metric's normal is still calibrating — no direction then.
/// `valueDate` / `today` (yyyy-MM-dd): an old reading ("Up" on a 16-day-old Readiness) gets none.
public nonisolated func kpiDetailStatus(history: [(date: String, value: Double?)], value: Double?,
                                        unit: String, decimals: Int, hubCalibrating: Bool = false,
                                        valueDate: String? = nil, today: String? = nil) -> KpiDetailStatus {
    guard let value, value.isFinite else {
        return KpiDetailStatus(word: "— \(JIMissingReason.noData.rawValue)", symbolName: "minus",
                               detail: "Nothing from this source yet.", role: .muted)
    }
    if let valueDate, let today, let age = kpiDayDistance(from: valueDate, to: today), age > kpiDetailFreshDays {
        return KpiDetailStatus(word: "— Old reading", symbolName: "minus",
                               detail: "The last reading is from \(kpiShortDay(valueDate)) — too old to compare with your average.",
                               role: .muted)
    }
    let window = history.sorted { $0.date < $1.date }.suffix(trendBaselineDays).compactMap(\.value)
    if hubCalibrating {
        return KpiDetailStatus(word: "— \(JIMissingReason.calibrating.rawValue)", symbolName: "minus",
                               detail: "Your normal is still being learned — no direction until it is set.", role: .muted)
    }
    guard window.count >= kpiDetailMinBaselineReadings, let baseline = trendAverage(history, days: trendBaselineDays) else {
        return KpiDetailStatus(word: "— \(JIMissingReason.calibrating.rawValue)", symbolName: "minus",
                               detail: "JI compares against your 28-day average once it has \(kpiDetailMinBaselineReadings) readings (\(window.count) so far).",
                               role: .muted)
    }
    let direction = trendDirection(recent: value, baseline: baseline)
    let word = switch direction { case .up: "Up"; case .down: "Down"; case .flat: "Steady"; case .unknown: "—" }
    let avg = kpiDetailNumber(baseline, decimals: decimals) + (unit.isEmpty ? "" : " \(unit)")
    return KpiDetailStatus(word: word, symbolName: direction.symbolName,
                           detail: "Your last reading against your 28-day average of \(avg).", role: .text)
}

/// W-FIX11 H1-16: the ONE number format on KPI detail — en_GB grouping, the Targets rows' too
/// ("4,179", "15,000 steps"); "—" when missing.
public nonisolated func kpiDetailNumber(_ v: Double?, decimals: Int) -> String {
    guard let v, v.isFinite else { return "—" }
    return jiGroupedNumber(v, decimals)
}

/// The chart axis' label: whole numbers without decimals, others with one.
public nonisolated func kpiAxisNumber(_ v: Double) -> String {
    jiGroupedNumber(v, v.rounded() == v ? 0 : 1)
}

/// Whole days from `from` to `to` (yyyy-MM-dd, UTC calendar); nil when either is unreadable.
nonisolated func kpiDayDistance(from: String, to: String) -> Int? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    guard let a = f.date(from: String(from.prefix(10))), let b = f.date(from: String(to.prefix(10))) else { return nil }
    return Int((b.timeIntervalSince(a) / 86_400).rounded())
}

/// "15 Sep" for yyyy-MM-dd.
nonisolated func kpiShortDay(_ iso: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
    let out = DateFormatter()
    out.locale = Locale(identifier: "en_GB"); out.timeZone = TimeZone(identifier: "UTC"); out.dateFormat = "d MMM"
    return out.string(from: d)
}

/// The value card: the number, its status word and the explanation line (board `03 KpiDetail`).
struct KpiDetailValueCard: View {
    let valueText: String
    let label: String
    let status: KpiDetailStatus
    let asOf: String?
    /// W-GUI R2: the numeral wears the metric colour (RHR coral, HRV blue); the sleep card is tinted.
    var tint: JIColorRole = .text
    var heroTint: Color? = nil
    private let theme = JITheme.native

    var body: some View {
        Surface(tint: heroTint) {
            VStack(alignment: .leading, spacing: 4) {
                Text(valueText)
                    .jiNumeral(.numeralLarge).foregroundStyle(theme.color(status.word.hasPrefix("—") ? .muted : tint))
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

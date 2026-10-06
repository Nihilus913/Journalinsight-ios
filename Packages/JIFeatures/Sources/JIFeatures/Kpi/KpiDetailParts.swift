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

/// W-FIX-P3 RG-82: 7 nights are drawn point to point — a smoothed curve through 7 points invents
/// values between nights; the 30 / 90 D lines stay smoothed.
public nonisolated func kpiTrendSmoothed(_ range: KpiDetailRange) -> Bool { range != .week }

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
    /// B-104 p2: HRV's merged Watch + Garmin runs (`kpiHrvSegments`); nil = draw `points` as one
    /// line, as every other metric does. Garmin runs are dashed in the muted tint ("est.").
    var segments: [KpiTrendSegment]? = nil
    /// B-104 p2: the extra caption under the legend (what the band / average are built from).
    var caption: String? = nil
    private let theme = JITheme.native
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180
    private var isEmpty: Bool { segments.map { $0.isEmpty } ?? points.isEmpty }

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
                    if let normal, !isEmpty {
                        RectangleMark(yStart: .value("Normal low", normal.low), yEnd: .value("Normal high", normal.high))
                            .foregroundStyle(theme.color(tint).opacity(0.14))
                            .accessibilityLabel("Your normal")
                            .accessibilityValue("\(jiNumber(normal.low, 1)) to \(jiNumber(normal.high, 1))")
                        // "dotted = median" (RG-82: dashed is the Garmin nights' style only).
                        RuleMark(y: .value("Median", normal.median))
                            .foregroundStyle(theme.color(tint).opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 4]))
                            .accessibilityLabel("Median")
                    }
                    if let segments {
                        ForEach(segments) { seg in
                            let color = theme.color(seg.isEstimate ? .muted : tint)
                            ForEach(seg.points) { p in
                                LineMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value),
                                         series: .value("Run", seg.id))
                                    .foregroundStyle(color)
                                    .lineStyle(StrokeStyle(lineWidth: seg.isEstimate ? 1.5 : 2, dash: seg.isEstimate ? [4, 3] : []))
                                    .interpolationMethod(kpiTrendSmoothed(range) ? .monotone : .linear)
                                if seg.points.count == 1 {
                                    PointMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                                        .foregroundStyle(color).symbolSize(seg.isEstimate ? 10 : 20)
                                }
                            }
                        }
                    } else {
                        ForEach(points) { p in
                            LineMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                                .foregroundStyle(theme.color(tint))
                                .interpolationMethod(kpiTrendSmoothed(range) ? .monotone : .linear)
                            if points.count == 1 {
                                PointMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value)).foregroundStyle(theme.color(tint))
                            }
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
                    if isEmpty { Text("No data yet").jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
                }
                .accessibilityLabel("\(label) trend")
                .accessibilityIdentifier("kpi-detail-chart")
                // W-GUI R2 (mockup 07): the legend is honest until W3 lands the band.
                Text(legend).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kpi-detail-legend")
                if let caption {
                    Text(caption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kpi-detail-chart-caption")
                }
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
    case .hrv: { $0.isWatchHrv ? $0.hrvMs : nil }   // B-104 p2: a Garmin estimate is not a Watch night
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
/// W-FIX12 F12-3: `normalSet` = whether the screen's 28-day row has a normal (`kpiDetailNormal`).
/// `false` = that row says "— Calibrating", so the headline names no direction either (Sleep
/// said "Down" over a Calibrating row). nil = the caller shows no such row (previews).
public nonisolated func kpiDetailStatus(history: [(date: String, value: Double?)], value: Double?,
                                        unit: String, decimals: Int, hubCalibrating: Bool = false,
                                        normalSet: Bool? = nil,
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
    if hubCalibrating || normalSet == false {
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
    guard let a = DayKey(iso: from), let b = DayKey(iso: to) else { return nil }
    return a.days(to: b)
}

/// "15 Sep" for yyyy-MM-dd.
nonisolated func kpiShortDay(_ iso: String) -> String {
    DayKey(iso: iso)?.string(format: "d MMM", locale: Locale(identifier: "en_GB")) ?? iso // W-FIX13 F-1
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

// MARK: - W-B67 R-3: "How this score is built" (Sleep KPI detail)

/// One component row of the sleep-score breakdown: label, `points / max` bar, the input it was
/// scored on, and where the night came from. Display only — the score is a shadow score.
public nonisolated struct SleepBreakdownRow: Equatable, Sendable, Identifiable {
    public let id: String          // duration | deep | rem | continuity
    public let title: String
    public let pointsText: String  // "5.7 / 20"
    public let fraction: Double    // points / max, clamped 0…1 for the bar
    public let input: String       // "31 min · 5 % of sleep, target 18 %" | "no data · credited 80 %"
    public let source: String?     // "Apple" | "Garmin"
}

public nonisolated let sleepBreakdownFooterText = "Shadow score — not a gate input"

/// "AppleHealth" → "Apple", "GarminAPI"/"GarminDB" → "Garmin"; anything else as served.
nonisolated func sleepBreakdownSourceLabel(_ label: String?) -> String? {
    guard let label, !label.isEmpty else { return nil }
    if label.hasPrefix("Apple") { return "Apple" }
    if label.hasPrefix("Garmin") { return "Garmin" }
    return label
}

/// A target share: "18 %" / "22.5 %" — whole percent unless it carries a tenth.
nonisolated func sleepBreakdownPercent(_ ratio: Double) -> String {
    let p = ratio * 100
    let tenth = (p * 10).rounded() / 10
    return tenth == tenth.rounded() ? "\(Int(tenth)) %" : String(format: "%.1f %%", tenth)
}

private nonisolated func sleepBreakdownMinutes(_ seconds: Int) -> String {
    let m = Int((Double(seconds) / 60).rounded())
    return m >= 60 ? DurationFormat.hoursPaddedMinutes(seconds: Double(seconds)) : "\(m) min"
}

/// The hub's (or the phone's own) breakdown as the four rows the Sleep detail lists.
public nonisolated func sleepBreakdownRows(_ breakdown: SleepScoreBreakdown, source: String?) -> [SleepBreakdownRow] {
    let src = sleepBreakdownSourceLabel(source)
    return breakdown.components.map { c in
        let title = switch c.key {
        case "duration": "Duration"
        case "deep": "Deep sleep"
        case "rem": "REM sleep"
        case "continuity": "Continuity"
        default: c.key.capitalized
        }
        let input: String
        if c.inferred || c.value == nil {
            input = "no data · credited 80 %"
        } else if let v = c.value {
            switch c.key {
            case "duration": input = DurationFormat.hoursPaddedMinutes(seconds: Double(v))
            case "continuity": input = "\(Int((Double(v) / 60).rounded())) min awake"
            default:
                var parts = [sleepBreakdownMinutes(v)]
                if let share = c.share, let target = c.target {
                    parts.append("\(Int((share * 100).rounded())) % of sleep, target \(sleepBreakdownPercent(target))")
                }
                input = parts.joined(separator: " · ")
            }
        } else { input = "—" }
        let fraction = c.max > 0 ? min(1, max(0, c.points / Double(c.max))) : 0
        return SleepBreakdownRow(id: c.key, title: title, pointsText: String(format: "%.1f / %d", c.points, c.max),
                                 fraction: fraction, input: input, source: src)
    }
}

public extension SleepScoreBreakdown {
    /// The phone's own computation (`JICompute.computeSleepScoreBreakdown`, Apple-native nights via
    /// `HKSleepNight.sleepScoreBreakdown`) in the hub's wire shape — one row builder for both.
    nonisolated init(computed: ComputedSleepBreakdown) {
        self.init(total: computed.total, components: computed.components.map {
            SleepScoreComponent(key: $0.key, points: $0.points, max: $0.max, value: $0.value,
                                share: $0.share, target: $0.target, inferred: $0.inferred)
        })
    }
}

/// The Sleep detail's "How this score is built" card: one row per component (bar = points / max),
/// then the shadow-score footer. Hidden by the caller when there is no breakdown (old hub).
struct SleepBreakdownSection: View {
    let rows: [SleepBreakdownRow]
    let total: Int?
    private let theme = JITheme.native

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            JISectionHeader("How this score is built")
            Surface(level: 1, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { JIRowDivider().padding(.leading, 0) }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: JISpacing.s3) {
                                Text(row.title).jiFont(.body).foregroundStyle(theme.color(.text))
                                Spacer(minLength: JISpacing.s2)
                                Text(row.pointsText).jiFont(.body, weight: .semibold).monospacedDigit()
                                    .foregroundStyle(theme.color(.text))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(theme.color(.muted).opacity(0.2))
                                    Capsule().fill(theme.color(.sleep)).frame(width: geo.size.width * row.fraction)
                                }
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                            HStack(alignment: .firstTextBaseline, spacing: JISpacing.s2) {
                                Text(row.input).jiFont(.caption).foregroundStyle(theme.color(.muted))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: JISpacing.s2)
                                if let source = row.source {
                                    Text(source).jiFont(.caption).foregroundStyle(theme.color(.muted))
                                }
                            }
                        }
                        .padding(.vertical, JISpacing.s3)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("kpi-sleep-breakdown-\(row.id)")
                    }
                }
                .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
            }
            Text((total.map { "\($0) points in all · " } ?? "") + sleepBreakdownFooterText)
                .jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
                .accessibilityIdentifier("kpi-sleep-breakdown-footer")
        }
        .accessibilityIdentifier("kpi-sleep-breakdown")
    }
}

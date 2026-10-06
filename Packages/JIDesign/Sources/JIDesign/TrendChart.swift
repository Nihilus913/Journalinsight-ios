import SwiftUI
import Charts

/// §2b.3 Health range picker. The provider filters points to the range; the chart only draws.
public nonisolated enum TrendRange: String, CaseIterable, Sendable, Equatable, Identifiable {
    case day = "D", week = "W", month = "M", sixMonths = "6M", year = "Y"
    public var id: String { rawValue }
    public var days: Int {
        switch self { case .day: 1; case .week: 7; case .month: 30; case .sixMonths: 182; case .year: 365 }
    }
}

public nonisolated struct TrendPoint: Sendable, Equatable, Identifiable {
    public let date: Date, value: Double
    public var id: Date { date }
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}

/// §8.4: a chart never lays out more than this many marks.
public nonisolated let trendChartMaxPoints = 400

/// Mean per bucket, bucket dated at its first sample. Identity when already within the cap.
public nonisolated func downsample(_ points: [TrendPoint], maxCount: Int = trendChartMaxPoints) -> [TrendPoint] {
    guard maxCount > 0, points.count > maxCount else { return points }
    let bucket = Int((Double(points.count) / Double(maxCount)).rounded(.up))
    return stride(from: 0, to: points.count, by: bucket).map { start in
        let slice = points[start..<min(start + bucket, points.count)]
        let mean = slice.reduce(0) { $0 + $1.value } / Double(slice.count)
        return TrendPoint(date: slice[slice.startIndex].date, value: mean)
    }
}

public nonisolated func trendAverage(_ points: [TrendPoint]) -> Double? {
    points.isEmpty ? nil : points.reduce(0) { $0 + $1.value } / Double(points.count)
}

/// Swift Charts in the Health axis style: trailing y-axis, dashed average rule, D/W/M/6M/Y
/// segmented picker above, "Show All Data ›" below. Empty → "No data yet" (rule 5).
/// W-GUI S1 (report §4.4): a SUM metric (steps, kcal) is bars from zero with a dashed goal;
/// a baseline metric stays a line with the dashed average.
public nonisolated enum TrendChartKind: Sendable, Equatable { case baseline, sum }

/// RG-11 / B-126 — one named line per data source (e.g. VO₂ max "Apple" solid vs "Garmin est."
/// dashed), so two sources on different scales never join into one saw-tooth line.
public nonisolated struct TrendSeries: Sendable, Equatable, Identifiable {
    public let name: String
    public let points: [TrendPoint]
    public let dashed: Bool
    public var id: String { name }
    public init(name: String, points: [TrendPoint], dashed: Bool) {
        self.name = name; self.points = points; self.dashed = dashed
    }
}

public struct TrendChart: View {
    let points: [TrendPoint], tint: Color, unit: String?, showAll: (() -> Void)?
    let kind: TrendChartKind, goal: Double?
    /// RG-11: when non-empty, draws one line per series (dashed where asked) instead of `points`,
    /// with a point mark per reading and no cross-source average rule.
    let series: [TrendSeries]
    /// RG-33: formats the y-axis ticks and the "avg" label (e.g. m:ss for pace); nil = plain number.
    let valueFormat: (@Sendable (Double) -> String)?
    @Binding var range: TrendRange
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    /// F2: how many date labels the x-axis asks for. Four fit at the default sizes; at an
    /// accessibility size each label is ~3× wider, so four of them truncate to "3 A…".
    private var xAxisLabelCount: Int { typeSize.isAccessibilitySize ? 2 : 4 }

    public init(points: [TrendPoint], tint: Color, unit: String?, range: Binding<TrendRange>, showAll: (() -> Void)?,
                kind: TrendChartKind = .baseline, goal: Double? = nil, series: [TrendSeries] = [],
                valueFormat: (@Sendable (Double) -> String)? = nil) {
        self.points = points; self.tint = tint; self.unit = unit; self._range = range; self.showAll = showAll
        self.kind = kind; self.goal = goal; self.series = series; self.valueFormat = valueFormat
    }

    /// RG-33: the average rule's label ("avg 10:23" for pace, "avg 152" otherwise).
    public nonisolated static func averageLabel(_ avg: Double, format: (@Sendable (Double) -> String)?) -> String {
        "avg " + (format?(avg) ?? avg.formatted(.number.precision(.fractionLength(0))))
    }

    public var body: some View {
        let shown = downsample(points)
        VStack(alignment: .leading, spacing: 12) {
            rangePicker

            Chart {
                ForEach(series) { s in
                    ForEach(downsample(s.points)) { p in
                        LineMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value),
                                 series: .value("Source", s.name))
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: s.dashed ? [5, 4] : []))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                            .foregroundStyle(tint)
                            .symbolSize(18)
                    }
                }
                ForEach(series.isEmpty ? shown : []) { p in
                    if kind == .sum {
                        BarMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                            .foregroundStyle(tint)
                            .cornerRadius(3)
                    } else {
                        LineMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                            .foregroundStyle(tint)
                            .interpolationMethod(.monotone)
                    }
                }
                if kind == .sum, let goal {
                    RuleMark(y: .value("Goal", goal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(theme.color(.muted))
                        .annotation(position: .top, alignment: .leading) {
                            Text("goal \(goal.formatted(.number.precision(.fractionLength(0))))").jiFont(.micro).foregroundStyle(theme.color(.muted))
                        }
                } else if series.isEmpty, let avg = trendAverage(shown) {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(theme.color(.muted))
                        // F2: leading, so the label never lands under the trailing y-axis labels.
                        .annotation(position: .top, alignment: .leading) {
                            Text(Self.averageLabel(avg, format: valueFormat)).jiFont(.micro).foregroundStyle(theme.color(.muted))
                        }
                }
            }
            .chartYAxis {
                if let valueFormat {
                    AxisMarks(position: .trailing) { v in
                        AxisGridLine(); AxisTick()
                        AxisValueLabel { if let d = v.as(Double.self) { Text(valueFormat(d)) } }
                    }
                } else {
                    AxisMarks(position: .trailing)
                }
            }
            // F2: fewer date labels, so none of them truncates ("3 A…") at AX3 / 440 pt.
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: xAxisLabelCount)) }
            .frame(minHeight: chartHeight)
            .overlay {
                if shown.isEmpty {
                    Text("No data yet").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                }
            }

            if let showAll {
                Button(action: showAll) {
                    HStack {
                        Text("Show All Data").jiFont(.body)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(theme.color(.info))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// `.segmented` is unavailable on watchOS (the WatchApp links this same JIDesign target),
    /// so the Watch gets the platform's own picker style instead of a compile error.
    @ViewBuilder private var rangePicker: some View {
        let picker = Picker("Range", selection: $range) {
            ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
        }
        #if os(watchOS)
        picker
        #else
        picker.pickerStyle(.segmented)
        #endif
    }
}

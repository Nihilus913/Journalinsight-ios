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
public struct TrendChart: View {
    let points: [TrendPoint], tint: Color, unit: String?, showAll: (() -> Void)?
    @Binding var range: TrendRange
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180

    /// F2: how many date labels the x-axis asks for. Four fit at the default sizes; at an
    /// accessibility size each label is ~3× wider, so four of them truncate to "3 A…".
    private var xAxisLabelCount: Int { typeSize.isAccessibilitySize ? 2 : 4 }

    public init(points: [TrendPoint], tint: Color, unit: String?, range: Binding<TrendRange>, showAll: (() -> Void)?) {
        self.points = points; self.tint = tint; self.unit = unit; self._range = range; self.showAll = showAll
    }

    public var body: some View {
        let shown = downsample(points)
        VStack(alignment: .leading, spacing: 12) {
            rangePicker

            Chart {
                ForEach(shown) { p in
                    LineMark(x: .value("Date", p.date), y: .value(unit ?? "Value", p.value))
                        .foregroundStyle(tint)
                        .interpolationMethod(.monotone)
                }
                if let avg = trendAverage(shown) {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(theme.color(.muted))
                        // F2: leading, so the label never lands under the trailing y-axis labels.
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg \(avg.formatted(.number.precision(.fractionLength(0))))").jiFont(.micro).foregroundStyle(theme.color(.muted))
                        }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing) }
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

import SwiftUI
import Charts

/// B-57 §1: one bar per night over the shaded normal band. `label` must be unique per point
/// (it is the categorical x value — a weekday over ≤ 7 nights is).
public nonisolated struct NormalBarPoint: Identifiable, Sendable, Equatable {
    public let id: String, label: String, value: Double?, isLatest: Bool
    /// Why `value` is nil — the word the empty slot shows under its "—" (rule 5).
    public let missingReason: JIMissingReason
    public init(id: String, label: String, value: Double?, isLatest: Bool, missingReason: JIMissingReason = .noData) {
        self.id = id; self.label = label; self.value = value; self.isLatest = isLatest; self.missingReason = missingReason
    }
}

/// What a slot prints above its bar: the number, or "—" plus the reason word for a missing night.
public nonisolated struct NormalBarSlotText: Sendable, Equatable {
    public let value: String, reason: String?
    public init(value: String, reason: String?) { self.value = value; self.reason = reason }
}

public nonisolated func normalBarSlotText(_ p: NormalBarPoint, decimals: Int) -> NormalBarSlotText {
    guard let v = p.value else { return NormalBarSlotText(value: "—", reason: p.missingReason.rawValue) }
    return NormalBarSlotText(value: jiNumber(v, decimals), reason: nil)
}

public nonisolated enum NormalBandPosition: Sendable, Equatable { case below, inside, above }

public nonisolated func normalBandPosition(_ value: Double?, normal: ClosedRange<Double>?) -> NormalBandPosition? {
    guard let value, let normal else { return nil }
    if value < normal.lowerBound { return .below }
    if value > normal.upperBound { return .above }
    return .inside
}

public nonisolated func normalBandWord(_ p: NormalBandPosition?) -> String? {
    switch p {
    case .below: JISignalStatus.belowNormal.word
    case .above: JISignalStatus.aboveNormal.word
    case .inside, .none: nil
    }
}

public nonisolated func normalBarChartLegend(normal: ClosedRange<Double>?, decimals: Int) -> String {
    guard let normal else { return "your normal — \(JIMissingReason.calibrating.rawValue) · last night" }
    return "your normal \(jiNumber(normal.lowerBound, decimals))–\(jiNumber(normal.upperBound, decimals)) · last night"
}

/// W-GUI S1 (report §4.4): the y-range follows the data and the band, never the zero floor
/// (HIG E7: a baseline metric has no meaningful zero). 10 % headroom each side; a flat series
/// gets ±1 unit so a point never sits on the edge.
public nonisolated func normalBarChartYDomain(points: [NormalBarPoint], normal: ClosedRange<Double>?, median: Double? = nil) -> ClosedRange<Double> {
    let values = points.compactMap(\.value) + [normal?.lowerBound, normal?.upperBound, median].compactMap { $0 }
    guard let lo = values.min(), let hi = values.max() else { return 0...1 }
    let span = max(hi - lo, 0)
    let pad = span > 0 ? span * 0.1 : 1
    return (lo - pad)...(hi + pad)
}

/// How many nights fell outside the band — worded in the legend, never colour alone.
public nonisolated func normalBarChartOutOfBandWord(points: [NormalBarPoint], normal: ClosedRange<Double>?) -> String? {
    guard normal != nil else { return nil }
    let n = points.filter { normalBandPosition($0.value, normal: normal).map { $0 != .inside } ?? false }.count
    guard n > 0 else { return nil }
    return n == 1 ? "1 night outside your normal" : "\(n) nights outside your normal"
}

/// The chart's title line: metric · window · source (report §4.4 — every chart names its source).
public nonisolated func normalBarChartTitle(metric: String, window: String, source: String?) -> String {
    [metric, window, source].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
}

public nonisolated func normalBarChartYMax(points: [NormalBarPoint], normal: ClosedRange<Double>?) -> Double {
    let top = (points.compactMap(\.value) + [normal?.upperBound].compactMap { $0 }).max() ?? 0
    return top > 0 ? top * 1.2 : 1
}

public nonisolated func normalBarChartAccessibilityLabel(points: [NormalBarPoint], normal: ClosedRange<Double>?, unit: String?, decimals: Int) -> String {
    let u = (unit?.isEmpty == false) ? " \(unit!)" : ""
    return points.map { p in
        guard let v = p.value else { return p.missingReason == .noData ? "\(p.label) no data" : "\(p.label) — \(p.missingReason.rawValue)" }
        let word = normalBandWord(normalBandPosition(v, normal: normal)).map { " \($0.lowercased())" } ?? ""
        return "\(p.label) \(jiNumber(v, decimals))\(u)\(word)"
    }.joined(separator: ", ")
}

/// At accessibility text sizes seven column labels cannot fit under the bars (they truncated to
/// "M…" / "Not in He…"), so the chart becomes one full-width row per night instead.
public nonisolated func normalBarChartStacks(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

/// A stacked row's bar length as a 0…1 share of the chart's scale; nil for a missing night.
public nonisolated func normalBarFraction(_ value: Double?, yMax: Double) -> Double? {
    guard let value, yMax > 0 else { return nil }
    return min(1, max(0, value / yMax))
}

public struct NormalBarChart: View {
    let points: [NormalBarPoint], normal: ClosedRange<Double>?, unit: String?, decimals: Int
    /// W-GUI S1: dashed median inside the band (only when given), the metric colour of the
    /// points, the title (metric · window · source) and the one-sentence summary above (E8).
    let median: Double?, tint: JIColorRole, title: String?, summary: String?
    @Environment(\.jiTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .body) private var stackedBarHeight: CGFloat = 8
    /// The chart's width, so a missing night's reason word wraps inside its own slot instead of
    /// running over its neighbours ("Not in Health yet" spanned two nights).
    @State private var chartWidth: CGFloat = 0
    private var slotWidth: CGFloat? {
        guard chartWidth > 0, !points.isEmpty else { return nil }
        return max(24, chartWidth / CGFloat(points.count) - 2)
    }

    public init(points: [NormalBarPoint], normal: ClosedRange<Double>?, unit: String? = nil, decimals: Int = 0,
                median: Double? = nil, tint: JIColorRole = .text, title: String? = nil, summary: String? = nil) {
        self.points = points; self.normal = normal; self.unit = unit; self.decimals = decimals
        self.median = median; self.tint = tint; self.title = title; self.summary = summary
    }

    /// W-GUI S1: every night wears the metric colour inside the band (or with no band); an
    /// out-of-band night is amber — and worded in the legend. The latest is bolder, not redder.
    private func barRole(_ p: NormalBarPoint) -> JIColorRole {
        guard p.value != nil else { return .mutedNested }
        return normalBandPosition(p.value, normal: normal) == .inside || normal == nil ? tint : .reduced
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                    .accessibilityAddTraits(.isHeader)
            }
            if let summary {
                Text(summary).jiFont(.footnote).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if points.isEmpty {
                Text("— \(JIMissingReason.noData.rawValue)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            } else if normalBarChartStacks(dynamicTypeSize) {
                stackedRows
                latestBandWord
            } else {
                // W-GUI S1 (report §4.4, Apple Vitals idiom): point marks in the shaded personal
                // band, dynamic y-range, band edges labelled on the y-axis, dashed median, missing
                // nights a hollow tick at the floor, the last value labelled beside its dot.
                let domain = normalBarChartYDomain(points: points, normal: normal, median: median)
                Chart {
                    if let normal {
                        RectangleMark(yStart: .value("Low", normal.lowerBound), yEnd: .value("High", normal.upperBound))
                            .foregroundStyle(theme.color(.mutedNested).opacity(0.28))
                    }
                    if let median, normal != nil {
                        RuleMark(y: .value("Median", median))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(theme.color(.muted))
                    }
                    ForEach(points) { p in
                        let slot = normalBarSlotText(p, decimals: decimals)
                        if let v = p.value {
                            PointMark(x: .value("Night", p.label), y: .value("Value", v))
                                .symbolSize(p.isLatest ? 110 : 64)
                                .foregroundStyle(theme.color(barRole(p)))
                                .annotation(position: p.isLatest ? .trailing : .top, spacing: 4) {
                                    if p.isLatest {
                                        Text(slot.value).jiFont(.caption, weight: .bold).foregroundStyle(theme.color(barRole(p)))
                                    }
                                }
                        } else {
                            // A missing night is a hollow tick at the floor with its reason word — never a fabricated point.
                            PointMark(x: .value("Night", p.label), y: .value("Value", domain.lowerBound))
                                .symbol { Circle().strokeBorder(theme.color(.muted), lineWidth: 1.5).frame(width: 9, height: 9) }
                                .annotation(position: .top, spacing: 2) {
                                    VStack(spacing: 0) {
                                        Text(slot.value).jiFont(.caption, weight: .semibold)
                                        if let reason = slot.reason {
                                            Text(reason).jiFont(.micro).multilineTextAlignment(.center)
                                                .lineLimit(3).minimumScaleFactor(0.7)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(width: slotWidth)
                                    .foregroundStyle(theme.color(.muted))
                                }
                        }
                    }
                }
                .chartXScale(domain: points.map(\.label))
                .chartYScale(domain: domain)
                .chartYAxis {
                    if let normal {
                        AxisMarks(position: .leading, values: [normal.lowerBound, normal.upperBound]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                            AxisValueLabel { if let v = value.as(Double.self) { Text(jiNumber(v, decimals)).jiFont(.micro) } }
                        }
                    } else {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                            AxisValueLabel { if let v = value.as(Double.self) { Text(jiNumber(v, decimals)).jiFont(.micro) } }
                        }
                    }
                }
                .frame(height: chartHeight)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chartWidth = $0 }
                latestBandWord
            }
            HStack(spacing: 6) {
                Text(normalBarChartLegend(normal: normal, decimals: decimals))
                if let word = normalBarChartOutOfBandWord(points: points, normal: normal) {
                    Text("·").accessibilityHidden(true)
                    Text(word).foregroundStyle(theme.color(.reduced))
                }
            }
            .jiFont(.caption).foregroundStyle(theme.color(.muted))
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last \(points.count) nights")
        .accessibilityValue(normalBarChartAccessibilityLabel(points: points, normal: normal, unit: unit, decimals: decimals))
    }

    @ViewBuilder private var latestBandWord: some View {
        if let latest = points.last(where: \.isLatest),
           let word = normalBandWord(normalBandPosition(latest.value, normal: normal)) {
            Text("\(latest.label) · \(word)").jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.reduced))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// AX sizes: label + value (or "—" + reason) on a line that wraps whole words, then a
    /// horizontal bar over the shaded normal band.
    private var stackedRows: some View {
        let yMax = normalBarChartYMax(points: points, normal: normal)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(points) { p in
                let slot = normalBarSlotText(p, decimals: decimals)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.label).jiFont(.footnote, weight: p.isLatest ? .bold : .regular)
                            .foregroundStyle(theme.color(.text))
                        Spacer(minLength: 8)
                        Text(slot.value).jiFont(.footnote, weight: p.isLatest ? .bold : .semibold)
                            .foregroundStyle(p.value == nil || !p.isLatest ? theme.color(.muted) : theme.color(barRole(p)))
                    }
                    if let reason = slot.reason {
                        Text(reason).jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.color(.mutedNested).opacity(0.2))
                            if let normal {
                                let lo = CGFloat(normalBarFraction(normal.lowerBound, yMax: yMax) ?? 0)
                                let hi = CGFloat(normalBarFraction(normal.upperBound, yMax: yMax) ?? 0)
                                Rectangle().fill(theme.color(.mutedNested).opacity(0.35))
                                    .frame(width: max(2, (hi - lo) * geo.size.width))
                                    .offset(x: lo * geo.size.width)
                            }
                            if let f = normalBarFraction(p.value, yMax: yMax) {
                                Capsule().fill(theme.color(barRole(p)))
                                    .frame(width: max(stackedBarHeight, CGFloat(f) * geo.size.width))
                            }
                        }
                    }
                    .frame(height: stackedBarHeight)
                }
            }
        }
    }
}

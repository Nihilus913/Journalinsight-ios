import SwiftUI

/// W-GUI S1 (report §4.4 "Square sparklines"): 7–14 points, the personal band when it is known
/// (`normal == nil` → no band, never a fake one), the last value labelled at its dot, and two
/// axis words ("14d ago" → "today"). A sparkline with no scale is removed, not kept — this one
/// always carries its words. `points` are oldest → newest; `nil` = a missing day (a gap).
/// W-FIX11 H1-10: `endLabel` = the last point's own day ("30 Sep") when it is not today — the axis
/// then ends on that day, never on "today".
public nonisolated func sparklineAxisWords(count: Int, endLabel: String? = nil) -> (start: String, end: String) {
    guard let endLabel else { return (count <= 1 ? "today" : "\(count - 1)d ago", "today") }
    return (count <= 1 ? endLabel : "\(count - 1)d earlier", endLabel)
}

/// W-FIX11 H1-11 (+H2-17): VoiceOver's sparkline summary. The last value keeps the data's own
/// precision (ACWR 1.764 → "1.76", never "2") even where the caller passed 0 decimals.
public nonisolated func sparklineAccessibilityLabel(points: [Double?], decimals: Int, unit: String?) -> String {
    guard let last = sparklineLastValue(points) else { return "no values yet" }
    let vals = points.compactMap { $0 }
    let integral = vals.allSatisfy { $0.rounded() == $0 }
    let shown = integral ? decimals : max(decimals, vals.allSatisfy { abs($0) < 10 } ? 2 : 1)
    return "last \(jiNumber(last, shown))\(unit.map { " \($0)" } ?? ""), \(points.count) days"
}

/// The last known value (the label beside the dot); nil when nothing is known.
public nonisolated func sparklineLastValue(_ points: [Double?]) -> Double? {
    points.compactMap { $0 }.last
}

public struct NormalSparkline: View {
    let points: [Double?], normal: ClosedRange<Double>?, tint: JIColorRole, color: Color?, unit: String?, decimals: Int
    /// The last-value label is optional: a card that already prints the value beside the line
    /// (SummaryCard) passes `false` so the number is never shown twice.
    let showsLastValue: Bool
    /// W-FIX11 H1-10: the last point's day when it is not today (nil = the line ends today).
    var endLabel: String? = nil
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 28

    public init(points: [Double?], normal: ClosedRange<Double>? = nil, tint: JIColorRole = .text, unit: String? = nil, decimals: Int = 0, showsLastValue: Bool = true, endLabel: String? = nil) {
        self.points = points; self.normal = normal; self.tint = tint; self.color = nil; self.unit = unit; self.decimals = decimals
        self.showsLastValue = showsLastValue; self.endLabel = endLabel
    }

    /// The same sparkline with a resolved colour (SummaryCard's `tint: Color`).
    public init(points: [Double?], normal: ClosedRange<Double>? = nil, color: Color, unit: String? = nil, decimals: Int = 0, showsLastValue: Bool = true, endLabel: String? = nil) {
        self.points = points; self.normal = normal; self.tint = .text; self.color = color; self.unit = unit; self.decimals = decimals
        self.showsLastValue = showsLastValue; self.endLabel = endLabel
    }

    private var lineColor: Color { color ?? theme.color(tint) }

    private var lastValue: Double? { sparklineLastValue(points) }

    public var body: some View {
        let vals = points.compactMap { $0 }
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { g in
                if vals.count >= 2 {
                    let scale = SparkScale(points: points, normal: normal, size: g.size)
                    ZStack(alignment: .topLeading) {
                        if let normal {
                            Rectangle().fill(theme.color(.mutedNested).opacity(0.28))
                                .frame(height: max(2, scale.y(normal.lowerBound) - scale.y(normal.upperBound)))
                                .offset(y: scale.y(normal.upperBound))
                        }
                        scale.path
                            .stroke(lineColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        if let lastIndex = points.lastIndex(where: { $0 != nil }), let v = points[lastIndex] {
                            Circle().fill(lineColor).frame(width: 6, height: 6)
                                .position(x: scale.x(lastIndex), y: scale.y(v))
                        }
                    }
                }
            }
            .frame(height: height)
            HStack {
                Text(sparklineAxisWords(count: points.count, endLabel: endLabel).start)
                Spacer(minLength: 4)
                if showsLastValue, let v = lastValue {
                    Text(jiNumber(v, decimals) + (unit.map { " \($0)" } ?? "")).foregroundStyle(lineColor).fontWeight(.semibold)
                }
                Spacer(minLength: 4)
                Text(sparklineAxisWords(count: points.count, endLabel: endLabel).end)
            }
            .jiFont(.micro).foregroundStyle(theme.color(.muted)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sparklineAccessibilityLabel(points: points, decimals: decimals, unit: unit))
    }
}

/// The sparkline's value → point mapping (pure; the y-range includes the band when known).
nonisolated struct SparkScale {
    let points: [Double?], size: CGSize, lo: Double, span: Double
    init(points: [Double?], normal: ClosedRange<Double>?, size: CGSize) {
        self.points = points; self.size = size
        let all = points.compactMap { $0 } + [normal?.lowerBound, normal?.upperBound].compactMap { $0 }
        lo = all.min() ?? 0
        span = max((all.max() ?? 1) - lo, 1e-9)
    }
    func y(_ v: Double) -> CGFloat { size.height * (1 - CGFloat((v - lo) / span)) }
    func x(_ i: Int) -> CGFloat { size.width * CGFloat(i) / CGFloat(max(points.count - 1, 1)) }
    var path: Path {
        Path { p in
            var first = true
            for (i, v) in points.enumerated() {
                guard let v else { first = true; continue }
                let pt = CGPoint(x: x(i), y: y(v))
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            }
        }
    }
}

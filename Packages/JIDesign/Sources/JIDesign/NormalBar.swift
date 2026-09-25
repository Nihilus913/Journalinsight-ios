import SwiftUI

/// B-57 §1: the sanctioned form for a baseline-relative metric (B-33 §4b amendment). One bar:
/// fill = the 7-day value, shaded band = the 28-day normal, white tick = median, amber tick = goal.
public nonisolated let normalBarLegendText = "fill = 7 days · shaded = your normal · median"
/// Every mark shares one 0…(top × headroom) axis, so the tallest mark never touches the end.
public nonisolated let normalBarHeadroom = 1.25

public nonisolated struct NormalBarGeometry: Equatable, Sendable {
    public let fill: Double?
    public let bandLower: Double?
    public let bandUpper: Double?
    public let median: Double?
    public let goal: Double?
}

/// Fractions 0…1 on the shared axis. `nil` when there is nothing positive to draw (rule 5: no
/// zero-length "bar" standing in for missing data).
public nonisolated func normalBarGeometry(value: Double?, normal: ClosedRange<Double>?, median: Double?, goal: Double?) -> NormalBarGeometry? {
    let marks = [value, normal?.upperBound, median, goal].compactMap { $0 }.filter { $0.isFinite }
    guard let top = marks.max(), top > 0 else { return nil }
    let scale = top * normalBarHeadroom
    func f(_ x: Double?) -> Double? { x.map { min(1, max(0, $0 / scale)) } }
    return NormalBarGeometry(fill: f(value), bandLower: f(normal?.lowerBound), bandUpper: f(normal?.upperBound),
                             median: f(median), goal: f(goal))
}

public nonisolated func normalBarCaption(normal: ClosedRange<Double>?, median: Double?, decimals: Int) -> String {
    guard let normal else { return "normal — \(JIMissingReason.calibrating.rawValue)" }
    var text = "normal \(jiNumber(normal.lowerBound, decimals))–\(jiNumber(normal.upperBound, decimals))"
    if let median { text += " · median \(jiNumber(median, decimals))" }
    return text
}

public nonisolated func normalBarAccessibilityValue(value: Double?, normal: ClosedRange<Double>?, median: Double?, goal: Double?, unit: String?, decimals: Int) -> String {
    let u = (unit?.isEmpty == false) ? " \(unit!)" : ""
    var parts: [String] = [value.map { "7 day value \(jiNumber($0, decimals))\(u)" } ?? "7 day value, no data"]
    if let normal {
        parts.append("your normal \(jiNumber(normal.lowerBound, decimals)) to \(jiNumber(normal.upperBound, decimals))")
    } else {
        parts.append("your normal still calibrating")
    }
    if let median { parts.append("median \(jiNumber(median, decimals))") }
    if let goal { parts.append("goal \(jiNumber(goal, decimals))\(u)") }
    return parts.joined(separator: ", ")
}

public struct NormalBar: View {
    let value: Double?, normal: ClosedRange<Double>?, median: Double?, goal: Double?
    let unit: String?, decimals: Int, tint: JIColorRole, showsCaption: Bool
    @Environment(\.jiTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 8

    public init(value: Double?, normal: ClosedRange<Double>?, median: Double? = nil, goal: Double? = nil,
                unit: String? = nil, decimals: Int = 0, tint: JIColorRole = .info, showsCaption: Bool = true) {
        self.value = value; self.normal = normal; self.median = median; self.goal = goal
        self.unit = unit; self.decimals = decimals; self.tint = tint; self.showsCaption = showsCaption
    }

    public var body: some View {
        let geo = normalBarGeometry(value: value, normal: normal, median: median, goal: goal)
        let tickHeight = barHeight * 2.4
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.color(.nested)).frame(height: barHeight)
                    if let lo = geo?.bandLower, let hi = geo?.bandUpper {
                        Capsule().fill(theme.color(.mutedNested).opacity(0.45))
                            .frame(width: max(barHeight, w * (hi - lo)), height: barHeight * 1.6)
                            .offset(x: w * lo)
                    }
                    if let f = geo?.fill, f > 0 {
                        Capsule().fill(theme.color(tint))
                            .frame(width: max(barHeight, w * f), height: barHeight)
                    }
                    if let m = geo?.median {
                        Rectangle().fill(theme.color(.text)).frame(width: 2, height: barHeight * 2).offset(x: w * m - 1)
                    }
                    if let gl = geo?.goal {
                        Rectangle().fill(theme.color(.reduced)).frame(width: 2, height: tickHeight).offset(x: w * gl - 1)
                    }
                }
                .frame(height: tickHeight)
                .animation(reduceMotion ? nil : JIMotion.standard, value: value)
            }
            .frame(height: tickHeight)
            if showsCaption {
                HStack(alignment: .firstTextBaseline) {
                    Text(normalBarCaption(normal: normal, median: median, decimals: decimals))
                        .jiFont(.caption).foregroundStyle(theme.color(.muted))
                    Spacer(minLength: 8)
                    if let goal {
                        Text("goal \(jiNumber(goal, decimals))").jiFont(.caption).foregroundStyle(theme.color(.reduced))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Against your normal")
        .accessibilityValue(normalBarAccessibilityValue(value: value, normal: normal, median: median, goal: goal, unit: unit, decimals: decimals))
    }
}

/// The one legend line a screen shows once above its bars.
public struct NormalBarLegend: View {
    @Environment(\.jiTheme) private var theme
    public init() {}
    public var body: some View {
        Text(normalBarLegendText).jiFont(.caption).foregroundStyle(theme.color(.muted))
            .accessibilityLabel("Legend: the fill is the last 7 days, the shaded band is your normal, the tick is the median")
    }
}

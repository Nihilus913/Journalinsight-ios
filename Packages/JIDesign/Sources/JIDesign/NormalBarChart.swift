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

public struct NormalBarChart: View {
    let points: [NormalBarPoint], normal: ClosedRange<Double>?, unit: String?, decimals: Int
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150

    public init(points: [NormalBarPoint], normal: ClosedRange<Double>?, unit: String? = nil, decimals: Int = 0) {
        self.points = points; self.normal = normal; self.unit = unit; self.decimals = decimals
    }

    private func barRole(_ p: NormalBarPoint) -> JIColorRole {
        guard p.isLatest else { return .mutedNested }
        return normalBandPosition(p.value, normal: normal) == .inside || normal == nil ? .info : .reduced
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if points.isEmpty {
                Text("— \(JIMissingReason.noData.rawValue)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
            } else {
                Chart(points) { p in
                    let slot = normalBarSlotText(p, decimals: decimals)
                    if let v = p.value {
                        BarMark(x: .value("Night", p.label), y: .value("Value", v), width: .ratio(0.5))
                            .foregroundStyle(theme.color(barRole(p)))
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                Text(slot.value).jiFont(.caption, weight: p.isLatest ? .bold : .regular)
                                    .foregroundStyle(p.isLatest ? theme.color(barRole(p)) : theme.color(.muted))
                            }
                    } else {
                        // A missing night keeps its slot: a visible "—" and the reason word, never a gap.
                        BarMark(x: .value("Night", p.label), y: .value("Value", 0), width: .ratio(0.5))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 2) {
                                VStack(spacing: 0) {
                                    Text(slot.value).jiFont(.caption, weight: .semibold)
                                    if let reason = slot.reason {
                                        Text(reason).jiFont(.micro).multilineTextAlignment(.center)
                                            .lineLimit(3).minimumScaleFactor(0.7)
                                    }
                                }
                                .foregroundStyle(theme.color(.muted))
                            }
                    }
                }
                .chartXScale(domain: points.map(\.label))
                .chartYScale(domain: 0...normalBarChartYMax(points: points, normal: normal))
                .chartYAxis(.hidden)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        if let normal, let anchor = proxy.plotFrame,
                           let yHi = proxy.position(forY: normal.upperBound),
                           let yLo = proxy.position(forY: normal.lowerBound) {
                            let rect = geo[anchor]
                            Rectangle().fill(theme.color(.mutedNested).opacity(0.35))
                                .frame(width: rect.width, height: max(2, yLo - yHi))
                                .position(x: rect.midX, y: rect.minY + (yHi + yLo) / 2)
                        }
                    }
                }
                .frame(height: chartHeight)
                if let latest = points.last(where: \.isLatest),
                   let word = normalBandWord(normalBandPosition(latest.value, normal: normal)) {
                    Text("\(latest.label) · \(word)").jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.reduced))
                }
            }
            Text(normalBarChartLegend(normal: normal, decimals: decimals)).jiFont(.caption).foregroundStyle(theme.color(.muted))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last \(points.count) nights")
        .accessibilityValue(normalBarChartAccessibilityLabel(points: points, normal: normal, unit: unit, decimals: decimals))
    }
}

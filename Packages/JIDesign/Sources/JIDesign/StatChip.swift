import SwiftUI

public struct StatChip: View {
    let label: String, value: Double?, unit: String?, points: [Double?], sourceMissing: Bool, action: (() -> Void)?
    public init(label: String, value: Double?, unit: String? = nil, points: [Double?] = [], sourceMissing: Bool = false, action: (() -> Void)? = nil) {
        self.label = label; self.value = value; self.unit = unit; self.points = points; self.sourceMissing = sourceMissing; self.action = action
    }
    public var body: some View {
        Button(action: { action?() }) {
            Surface(level: 2, padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption).foregroundStyle(JIColor.muted).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(numeral).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(JIColor.text)
                            .contentTransition(.numericText())
                        if let unit, showsUnit { Text(unit).font(.caption).foregroundStyle(JIColor.muted) }
                    }
                    Sparkline(points: points).frame(height: 18)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.pressableScale)
        .disabled(action == nil)
        .accessibilityLabel(statChipAccessibilityLabel(label: label, numeral: numeral, unit: unit, showsUnit: showsUnit, sourceMissing: sourceMissing))
    }
    /// Unit is shown (visually and to VoiceOver) only when there is a real value to attach it to.
    private var showsUnit: Bool { value != nil && !sourceMissing }
    private var numeral: String {
        if sourceMissing { return "—" }
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}

/// DESIGN-6: a source-missing chip announces the shared "not from current source" copy —
/// never a bare "—" with a dangling unit. Pure + testable independent of SwiftUI's view
/// lifecycle (mirrors the ReadinessArcGauge/EAGatedTile/DriverBars label builders).
public nonisolated func statChipAccessibilityLabel(label: String, numeral: String, unit: String?, showsUnit: Bool, sourceMissing: Bool) -> String {
    if sourceMissing { return [label, sourceMissingCopy].joined(separator: " ") }
    return [label, numeral, showsUnit ? unit : nil].compactMap { $0 }.joined(separator: " ")
}

/// Neutral gray, always — sparklines never carry the reserved verdict green.
public struct Sparkline: View {
    let points: [Double?]
    public init(points: [Double?]) { self.points = points }
    public var body: some View {
        GeometryReader { g in
            let vals = points.compactMap { $0 }
            if vals.count >= 2, let lo = vals.min(), let hi = vals.max() {
                let span = max(hi - lo, 1e-9)
                Path { p in
                    var first = true
                    for (i, v) in points.enumerated() {
                        guard let v else { first = true; continue }
                        let x = g.size.width * CGFloat(i) / CGFloat(max(points.count - 1, 1))
                        let y = g.size.height * (1 - CGFloat((v - lo) / span))
                        if first { p.move(to: CGPoint(x: x, y: y)); first = false } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }.stroke(JIColor.mutedNested, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}

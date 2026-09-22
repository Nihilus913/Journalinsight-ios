import SwiftUI

public struct StatChip: View {
    let label: String, value: Double?, unit: String?, points: [Double?], sourceMissing: Bool, action: (() -> Void)?
    /// B-46 item 3 (fixer): the day a fallback reading was actually taken on ("as of Sep 15"),
    /// already humanised by `kpiAsOfLabel`. `nil` = the reading IS today's, so nothing is shown.
    public let asOf: String?
    /// Accessibility identifier for the as-of line, so a sweep/UI test can assert the label is
    /// RENDERED and not merely computed (the exact defect this fixer closes).
    public let asOfIdentifier: String?
    /// B-47: the metric's own colour (`metricTintRole`), carried by the value and its unit like
    /// Apple Fitness's Summary cards. `.text` — the default — is the old, untinted look, so an
    /// existing call site keeps rendering exactly as it did.
    public let tint: JIColorRole
    @Environment(\.jiTheme) private var theme
    public init(label: String, value: Double?, unit: String? = nil, points: [Double?] = [], sourceMissing: Bool = false, asOf: String? = nil, asOfIdentifier: String? = nil, tint: JIColorRole = .text, action: (() -> Void)? = nil) {
        self.label = label; self.value = value; self.unit = unit; self.points = points; self.sourceMissing = sourceMissing
        self.asOf = asOf; self.asOfIdentifier = asOfIdentifier; self.tint = tint; self.action = action
    }
    public var body: some View {
        Button(action: { action?() }) {
            Surface(level: 2, padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // B-47: `jiFont`, not a raw `.font(.caption)` — this label was the one text
                    // site in JIDesign that never went through the token scale at all.
                    Text(label).jiFont(.subheadline).foregroundStyle(theme.color(.muted)).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(numeral).jiNumeral(.numeralCompact, tint: valueTint)
                            .contentTransition(.numericText())
                        // The unit rides the value's colour at ~70 % of its size (Fitness's
                        // "13/980 CAL"), never a muted caption hanging off a coloured numeral.
                        if let unit, showsUnit { Text(unit).jiFont(.subheadline, weight: .semibold, tint: valueTint) }
                    }
                    if let asOf, !sourceMissing {
                        Text(asOf).jiFont(.caption).foregroundStyle(theme.color(.muted)).lineLimit(1)
                            .accessibilityIdentifier(asOfIdentifier ?? "")
                    }
                    Sparkline(points: points).frame(height: 18)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.pressableScale)
        .disabled(action == nil)
        .accessibilityLabel(statChipAccessibilityLabel(label: label, numeral: numeral, unit: unit, showsUnit: showsUnit, sourceMissing: sourceMissing, asOf: asOf))
    }
    /// No value = no colour: an empty or gated chip is muted, exactly like `TrendRow`'s "-/-" rows.
    private var valueTint: JIColorRole { (value == nil || sourceMissing) ? .muted : tint }

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
public nonisolated func statChipAccessibilityLabel(label: String, numeral: String, unit: String?, showsUnit: Bool, sourceMissing: Bool, asOf: String? = nil) -> String {
    if sourceMissing { return [label, sourceMissingCopy].joined(separator: " ") }
    return [label, numeral, showsUnit ? unit : nil, asOf].compactMap { $0 }.joined(separator: " ")
}

/// Neutral gray, always — sparklines never carry the reserved verdict green.
public struct Sparkline: View {
    let points: [Double?]
    @Environment(\.jiTheme) private var theme
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
                }.stroke(theme.color(.mutedNested), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}

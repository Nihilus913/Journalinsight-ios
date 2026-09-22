import SwiftUI

/// Rule 5 + DESIGN-6: never a bare dash — "no data yet" or the shared source-missing copy.
public nonisolated func summaryCardAccessibilityLabel(title: String, value: String?, unit: String?, timestamp: String?, sourceMissing: Bool) -> String {
    if sourceMissing { return "\(title) \(sourceMissingCopy)" }
    guard let value else { return "\(title), no data yet" }
    let head = [title, value, unit].compactMap { $0 }.joined(separator: " ")
    return timestamp.map { "\(head), \($0)" } ?? head
}

/// §2b.1 Health "Summary" card: tinted symbol + category label, big value + unit, timestamp,
/// trailing 7-day sparkline, chevron when tappable. The card is the tap target.
public struct SummaryCard: View {
    let icon: String, tint: Color, title: String, value: String?, unit: String?, timestamp: String?
    let sparkline: [Double?], sourceMissing: Bool, action: (() -> Void)?
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var sparkWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var sparkHeight: CGFloat = 24

    public init(icon: String, tint: Color, title: String, value: String?, unit: String? = nil, timestamp: String? = nil,
                sparkline: [Double?] = [], sourceMissing: Bool = false, action: (() -> Void)? = nil) {
        self.icon = icon; self.tint = tint; self.title = title; self.value = value; self.unit = unit
        self.timestamp = timestamp; self.sparkline = sparkline; self.sourceMissing = sourceMissing; self.action = action
    }

    public var body: some View {
        Button(action: { action?() }) {
            Surface(level: 1) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: icon).foregroundStyle(tint)
                        // B-47: Fitness sets the card title in primary text at `.title3` bold and
                        // tints the VALUE — the icon already carries the metric's colour.
                        Text(title).jiFont(.cardTitle).foregroundStyle(theme.color(.text))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        if action != nil {
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.color(.mutedNested))
                        }
                    }
                    // B-47 fix: at half width (2-up grid) the value and the 64 pt sparkline do not
                    // fit on one row. `numeral`/`unitText` are hard-limited to one line, so their
                    // ideal width is the TRUE single-line width and `ViewThatFits` can reject the
                    // side-by-side candidate instead of silently wrapping the number. The fallback
                    // puts the sparkline on its own row under the value (Apple Fitness idiom).
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom, spacing: 12) { valueRow; Spacer(minLength: 0); sparklineView }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .bottom, spacing: 12) { valueRow; Spacer(minLength: 0) }
                            sparklineView
                        }
                    }
                    if sourceMissing {
                        Text(sourceMissingCopy).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    } else if let timestamp {
                        Text(timestamp).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.pressableScale)
        .disabled(action == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryCardAccessibilityLabel(title: title, value: value, unit: unit, timestamp: timestamp, sourceMissing: sourceMissing))
    }

    /// Value + unit, side by side when they fit, stacked otherwise. Never wraps a number.
    /// Internal (not private) so the B-47 no-wrap regression test can measure it in isolation.
    var valueRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 3) { numeral; unitText }
            VStack(alignment: .leading, spacing: 0) { numeral; unitText }
        }
    }

    @ViewBuilder private var sparklineView: some View {
        if sparkline.compactMap({ $0 }).count >= 2 {
            Sparkline(points: sparkline).frame(width: sparkWidth, height: sparkHeight)
        }
    }

    /// Internal (not private) so the B-47 no-wrap regression test can measure it alone.
    var numeral: some View {
        Text(sourceMissing ? "—" : (value ?? "—"))
            .jiNumeral(.numeralCompact)
            .foregroundStyle(value == nil || sourceMissing ? theme.color(.muted) : tint)
            // A number is never broken across lines; it shrinks first (the title already does this).
            .lineLimit(1).minimumScaleFactor(0.6)
            .contentTransition(.numericText())
    }

    @ViewBuilder private var unitText: some View {
        if let unit, value != nil, !sourceMissing {
            Text(unit).jiFont(.subheadline, weight: .semibold).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

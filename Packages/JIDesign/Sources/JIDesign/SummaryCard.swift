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
                    HStack(alignment: .bottom, spacing: 12) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) { numeral; unitText }
                            VStack(alignment: .leading, spacing: 0) { numeral; unitText }
                        }
                        Spacer(minLength: 0)
                        if sparkline.compactMap({ $0 }).count >= 2 {
                            Sparkline(points: sparkline).frame(width: sparkWidth, height: sparkHeight)
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

    private var numeral: some View {
        Text(sourceMissing ? "—" : (value ?? "—"))
            .jiNumeral(.numeralCompact)
            .foregroundStyle(value == nil || sourceMissing ? theme.color(.muted) : tint)
            .contentTransition(.numericText())
    }

    @ViewBuilder private var unitText: some View {
        if let unit, value != nil, !sourceMissing {
            Text(unit).jiFont(.subheadline, weight: .semibold).foregroundStyle(tint)
        }
    }
}

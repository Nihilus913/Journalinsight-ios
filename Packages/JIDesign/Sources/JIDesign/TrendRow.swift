import SwiftUI

/// B-42 (W-B46 L2) — one line of the Today **Trends** card, after Apple Fitness's Summary →
/// Trends block (`docs/design/references/2026-09-22-apple-fitness-summary.png`): a coloured pill,
/// the metric name, and the 7-day average against the 28-day baseline with a direction arrow.
///
/// Direction only; never a verdict. The reserved go/red palette stays out of it (rule 6) — the
/// caller passes the metric's own tint, and "better" vs "worse" is deliberately not encoded,
/// because for RHR down is good and for HRV up is (the arrow states the fact, the KPI screen
/// interprets it).
public nonisolated enum JITrendDirection: String, Sendable, Equatable, CaseIterable {
    case up, down, flat, unknown

    /// SF Symbol for the arrow at the end of the row.
    public var symbolName: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .flat: "arrow.right"
        case .unknown: "minus"
        }
    }

    /// Spoken by VoiceOver in place of the glyph.
    public var spokenName: String {
        switch self {
        case .up: "trending up"
        case .down: "trending down"
        case .flat: "flat"
        case .unknown: "no trend yet"
        }
    }
}

/// Pure comparison of a recent average against a longer baseline. `.unknown` when either side is
/// missing or the baseline is zero (no percentage to take); `.flat` when the relative change is
/// within `tolerance` (default 2 %, the band Apple's own "—" rows sit in), so day-to-day noise
/// never reads as a direction.
public nonisolated func trendDirection(recent: Double?, baseline: Double?, tolerance: Double = 0.02) -> JITrendDirection {
    guard let recent, let baseline, baseline != 0 else { return .unknown }
    let change = (recent - baseline) / abs(baseline)
    if abs(change) < tolerance { return .flat }
    return change > 0 ? .up : .down
}

/// The "7 d vs 28 d" figure pair, formatted like Apple's `13/980 CAL` line: both numbers at the
/// metric's own precision, the unit once at the end. `nil` on either side renders as an em dash,
/// never as a zero (rule 5).
public nonisolated func trendValueText(recent: Double?, baseline: Double?, unit: String?, decimals: Int = 0) -> String {
    func fmt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number.precision(.fractionLength(decimals)))
    }
    let pair = "\(fmt(recent)) vs \(fmt(baseline))"
    guard let unit, !unit.isEmpty, recent != nil || baseline != nil else { return pair }
    return "\(pair) \(unit)"
}

/// VoiceOver copy for a whole row — pure so it is tested without a view harness (same idiom as
/// `statChipAccessibilityLabel`).
public nonisolated func trendRowAccessibilityLabel(name: String, recent: Double?, baseline: Double?, unit: String?, decimals: Int, direction: JITrendDirection) -> String {
    "\(name), 7 day average \(trendValueText(recent: recent, baseline: baseline, unit: unit, decimals: decimals)) 28 day average, \(direction.spokenName)"
}

public struct TrendRow: View {
    let name: String, recent: Double?, baseline: Double?, unit: String?, decimals: Int, tint: Color
    @Environment(\.jiTheme) private var theme

    public init(name: String, recent: Double?, baseline: Double?, unit: String? = nil, decimals: Int = 0, tint: Color) {
        self.name = name; self.recent = recent; self.baseline = baseline
        self.unit = unit; self.decimals = decimals; self.tint = tint
    }

    public var direction: JITrendDirection { trendDirection(recent: recent, baseline: baseline) }
    /// A row with nothing to show is muted, like Apple's "-/-" rows — the metric's colour is for
    /// rows that actually carry a figure.
    private var valueTint: Color { recent == nil && baseline == nil ? theme.color(.muted) : tint }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Apple's leading pill: a flat capsule in the metric's colour, inside a neutral disc.
            Capsule().fill(tint).frame(width: 22, height: 5)
                .padding(.vertical, 9).padding(.horizontal, 5)
                .background(theme.color(.nested), in: Circle())
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Text(trendValueText(recent: recent, baseline: baseline, unit: unit, decimals: decimals))
                        .jiFont(.caption, weight: .semibold).foregroundStyle(valueTint)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Image(systemName: direction.symbolName)
                        .font(.caption2.weight(.bold)).foregroundStyle(valueTint)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trendRowAccessibilityLabel(name: name, recent: recent, baseline: baseline, unit: unit, decimals: decimals, direction: direction))
    }
}

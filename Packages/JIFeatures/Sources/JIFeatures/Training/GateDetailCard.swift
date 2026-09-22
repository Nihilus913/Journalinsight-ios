import SwiftUI
import JICore
import JIDesign

/// Slim readiness summary + gate recommendation (oracle: `GateDetailCard.tsx`). No "gate-rationale"
/// drill-down screen this wave (W3b scope) — the card renders the same two lines without the
/// tap-through chevron/navigation.
public struct GateDetailCard: View {
    let morning: MorningResponse?
    let gate: GateResponse?
    /// B-45 (d): the hub's verdict is whatever day `scripts/morning_go.py` last wrote. When that
    /// is not today, the card says so instead of letting the date read as "now".
    let isStale: Bool
    @Environment(\.jiTheme) private var theme
    public init(morning: MorningResponse?, gate: GateResponse?, isStale: Bool = false) {
        self.morning = morning; self.gate = gate; self.isStale = isStale
    }

    public var body: some View {
        let v = verdictParts(morning?.verdict)
        Surface {
            VStack(alignment: .leading, spacing: 2) {
                Text(isStale ? "Readiness from \(morning?.verdictDate ?? "—")" : "Readiness · \(morning?.verdictDate ?? "—")")
                    .font(.caption.weight(.semibold)).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("gate-detail-date")
                Text(v.word)
                    .font(.title3.bold())
                    .foregroundStyle(trainingToneColor(v.tone, theme))
                if isStale {
                    Text("No verdict for today yet — this is the last one the hub wrote.")
                        .font(.caption).foregroundStyle(theme.color(.reduced)).padding(.top, 2)
                        .accessibilityIdentifier("gate-detail-stale")
                }
                Text("Gate recommendation: \(gateRecommendationLabel)")
                    .font(.footnote).foregroundStyle(theme.color(.muted)).padding(.top, 2)
            }
            // B-46 item 7: `Surface` sizes to its content, so a short card sat narrower than its
            // neighbours. Every card on these screens fills the column instead.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Readiness verdict details")
        .accessibilityValue("\(verdictParts(morning?.verdict).word), gate recommendation \(gateRecommendationLabel)")
        .accessibilityIdentifier("gate-detail-card")
    }

    private var gateRecommendationLabel: String {
        guard let gate else { return "—" }
        switch gate.recommendation {
        case .progress: return "PROGRESS"
        case .maintain: return "MAINTAIN"
        case .reduce: return "REDUCE"
        case .insufficientData: return "INSUFFICIENT_DATA"
        }
    }
}

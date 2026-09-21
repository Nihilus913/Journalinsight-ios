import SwiftUI
import JICore
import JIDesign

/// Slim readiness summary + gate recommendation (oracle: `GateDetailCard.tsx`). No "gate-rationale"
/// drill-down screen this wave (W3b scope) — the card renders the same two lines without the
/// tap-through chevron/navigation.
public struct GateDetailCard: View {
    let morning: MorningResponse?
    let gate: GateResponse?
    @Environment(\.jiTheme) private var theme
    public init(morning: MorningResponse?, gate: GateResponse?) { self.morning = morning; self.gate = gate }

    public var body: some View {
        let v = verdictParts(morning?.verdict)
        Surface {
            VStack(alignment: .leading, spacing: 2) {
                Text("Readiness · \(morning?.verdictDate ?? "—")")
                    .font(.caption.weight(.semibold)).foregroundStyle(theme.color(.muted))
                Text(v.word)
                    .font(.title3.bold())
                    .foregroundStyle(trainingToneColor(v.tone, theme))
                Text("Gate recommendation: \(gateRecommendationLabel)")
                    .font(.footnote).foregroundStyle(theme.color(.muted)).padding(.top, 2)
            }
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

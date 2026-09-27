import SwiftUI
import JICore
import JICompute
import JIDesign

/// B-57 W3 S1 — the card's words, pure: the number only when there is a score, else "—" plus the
/// honest reason ("Calibrating · n of 14 nights" / "No data"); never 0 and never 50 (rule 5).
/// The score may wear verdict green (rule 6: 0–100 score); a low one is amber.
public nonisolated func recoveryScoreCardText(result: RecoveryScoreResult?, reasonWord: String?)
    -> (numeral: String, caption: String, role: JIColorRole) {
    guard let result else { return ("—", reasonWord ?? JIMissingReason.noData.rawValue, .muted) }
    switch result.status {
    case .calibrating:
        let n = min(max(result.nights, 0), result.nightsNeeded)
        return ("—", "\(JIMissingReason.calibrating.rawValue) · \(n) of \(result.nightsNeeded) nights", .muted)
    case .missing:
        return ("—", JIMissingReason.noData.rawValue, .muted)
    case .ok:
        guard let score = result.score else { return ("—", JIMissingReason.noData.rawValue, .muted) }
        let low = score < RecoveryScore.lowScore
        return ("\(score)", low ? "Recovery low" : "In your normal range", low ? .reduced : .go)
    }
}

/// B-57 W3 — the recovery-score card (boards `1 Today/01 Decide` compact, `03 GateRationale` full).
/// Display-only: the verdict still comes from the hub (spec §0.4). The number is the on-device
/// score over the gate's own inputs (`/vitals/recovery-inputs`, `RecoveryInsightService`).
/// `compact` is Decide's row inside the "What drove it" card; the full card adds the driver bars
/// and the note.
public struct RecoveryScoreCard: View {
    @Environment(\.recoveryInsight) private var insight
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiOffscreenRender) private var offscreen
    private let compact: Bool

    public init(compact: Bool = false) { self.compact = compact }

    /// The gate's own `recovery` signal: the card shows it, so no second SignalRow / counted row.
    public nonisolated static func visibleSignals(_ signals: [GateSignal]) -> [GateSignal] {
        signals.filter { $0.key != "recovery" }
    }

    private var model: RecoveryCardModel {
        RecoveryCardModel.make(result: insight?.result, reasonWord: insight == nil ? JIMissingReason.noData.rawValue : insight?.reasonWord,
                               sleepGoalH: MorningGateConfig.default.sleepGoalH)
    }

    public var body: some View {
        let text = recoveryScoreCardText(result: insight?.result, reasonWord: insight == nil ? nil : insight?.reasonWord)
        Group {
            if compact {
                compactRow(text)
            } else {
                Surface(level: 1, padding: JISpacing.cardPadding) {
                    VStack(alignment: .leading, spacing: JISpacing.s3) {
                        headline(text, token: .numeralMedium)
                        DriverBars(drivers: model.drivers)
                        Text(RecoveryCardModel.note).jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier(compact ? "today.decide.recoveryScore" : "gateRationale.score")
        .task { if !offscreen { await insight?.refreshIfStale() } }
    }

    private func headline(_ text: (numeral: String, caption: String, role: JIColorRole), token: JITypography.Token) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JISpacing.s2) {
            Text(text.numeral).jiNumeral(token, weight: .heavy, tint: text.role)
            Text(text.caption).jiFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.color(text.role == .go ? .muted : text.role))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery score, \(text.numeral == "—" ? "" : "\(text.numeral), ")\(text.caption)")
    }

    /// Decide: one row in the grouped card, the same icon well + title as the signal rows' card.
    private func compactRow(_ text: (numeral: String, caption: String, role: JIColorRole)) -> some View {
        let label = Text("Recovery score").jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
        let value = HStack(alignment: .firstTextBaseline, spacing: JISpacing.s2) {
            Text(text.numeral).jiNumeral(.numeralSmall, weight: .heavy, tint: text.role)
            Text(text.caption).jiFont(.footnote, weight: .semibold)
                .foregroundStyle(theme.color(text.role == .go ? .muted : text.role))
                .fixedSize(horizontal: false, vertical: true)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { label.fixedSize(); Spacer(minLength: JISpacing.s2); value }
            VStack(alignment: .leading, spacing: 2) { label; value }
        }
        .padding(.vertical, JISpacing.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery score, \(text.numeral == "—" ? "" : "\(text.numeral), ")\(text.caption)")
    }
}

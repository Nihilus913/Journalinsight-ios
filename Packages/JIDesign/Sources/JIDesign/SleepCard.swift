import SwiftUI
import JICore

/// The sleep score is a 0–100 band/score, so the reserved verdict green is
/// allowed here ONLY (rule 6) — never on the card chrome, the duration line, or any sub-bar.
/// B-33 Phase C: returns a ROLE, not a `Color` — the active theme resolves it in `body`, which
/// keeps the helper pure and `nonisolated` (JIDesign's default isolation is MainActor).
public nonisolated func sleepScoreColorRole(score: Double?, sourceMissing: Bool) -> JIColorRole {
    guard !sourceMissing, let score else { return .muted }
    switch bandTone(for: score) {
    case .go: return .go
    case .amber: return .reduced
    case .red: return .danger
    case .muted: return .muted
    }
}

/// Sleep duration + the 0–100 sleep score. Card accent is sleep-purple (`.sleep`);
/// the score itself is a band/score, so the reserved verdict green is allowed ON THE SCORE ONLY
/// (rule 6 — never on the card chrome or the duration line).
public struct SleepCard: View {
    let durationSec: Double?, score: Double?, sourceMissing: Bool
    @Environment(\.jiTheme) private var theme
    public init(durationSec: Double?, score: Double?, sourceMissing: Bool = false) {
        self.durationSec = durationSec; self.score = score; self.sourceMissing = sourceMissing
    }

    public var body: some View {
        Surface(level: 2, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(theme.color(.sleep)).frame(width: 8, height: 8)
                    Text("Sleep").font(.caption).foregroundStyle(theme.color(.muted))
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(durationText).jiNumeral(.numeralSmall).foregroundStyle(theme.color(.text))
                        Text("duration").font(.caption2).foregroundStyle(theme.color(.muted))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scoreText)
                            .jiNumeral(.numeralSmall)
                            .foregroundStyle(scoreColor)
                        Text("score").font(.caption2).foregroundStyle(theme.color(.muted))
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep, \(durationText) duration, score \(scoreText)")
    }

    private var durationText: String {
        guard !sourceMissing, let durationSec else { return sourceMissing ? "Not from the current source" : "—" }
        let hrs = Int(durationSec) / 3600, mins = (Int(durationSec) % 3600) / 60
        return "\(hrs)h \(mins)m"
    }
    private var scoreText: String {
        guard !sourceMissing, let score else { return sourceMissing ? "Not from the current source" : "—" }
        return score.formatted(.number.precision(.fractionLength(0)))
    }
    /// Green ONLY here — the score is a 0–100 band, the one place the reserved color is allowed.
    private var scoreColor: Color { theme.color(sleepScoreColorRole(score: score, sourceMissing: sourceMissing)) }
}

private nonisolated func bandTone(for score: Double) -> VerdictTone {
    switch readinessBand(for: score) { case .go: .go; case .warn: .amber; case .danger: .red }
}

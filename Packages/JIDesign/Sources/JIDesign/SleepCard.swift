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
    /// W-GUI-2 S3 (mockup 03): the ONE tinted hero card of a screen may be the sleep card —
    /// sleep-blue 16 % → 3 % top to bottom (`Surface(tint:)`); off by default (nested tile look).
    let tinted: Bool
    @Environment(\.jiTheme) private var theme
    public init(durationSec: Double?, score: Double?, sourceMissing: Bool = false, tinted: Bool = false) {
        self.durationSec = durationSec; self.score = score; self.sourceMissing = sourceMissing; self.tinted = tinted
    }

    public var body: some View {
        Surface(level: tinted ? 1 : 2, padding: JISpacing.cardPadding, tint: tinted ? theme.color(.sleep) : nil) {
            VStack(alignment: .leading, spacing: JISpacing.s2 + 2) {
                HStack(spacing: JISpacing.s1 + 2) {
                    Circle().fill(theme.color(.sleep)).frame(width: 8, height: 8)
                    // W-GUI-2 S3: token scale (report §4.5), never a raw `.font(.caption)`.
                    Text("Sleep").jiFont(.caption).foregroundStyle(theme.color(.muted))
                }
                HStack(alignment: .firstTextBaseline, spacing: JISpacing.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(durationText).jiNumeral(.numeralSmall).foregroundStyle(theme.color(.text))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("duration").jiFont(.micro).foregroundStyle(theme.color(.muted))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scoreText)
                            .jiNumeral(.numeralSmall)
                            .foregroundStyle(scoreColor)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("score").jiFont(.micro).foregroundStyle(theme.color(.muted))
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

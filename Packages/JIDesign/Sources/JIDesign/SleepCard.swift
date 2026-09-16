import SwiftUI
import JICore

/// The sleep score is a 0–100 band/score, so the reserved verdict green is
/// allowed here ONLY (rule 6) — never on the card chrome, the duration line, or any sub-bar.
/// Not `nonisolated`: it calls MainActor-isolated `JIColor.muted`/`JIColor.color(for:)`
/// (JIDesign's default isolation — see ReadinessArcGauge.swift's `bandColor`).
public func sleepScoreColor(score: Double?, sourceMissing: Bool) -> Color {
    guard !sourceMissing, let score else { return JIColor.muted }
    return JIColor.color(for: bandTone(for: score))
}

/// Sleep duration + the 0–100 sleep score. Card accent is sleep-purple (`JIColor.sleep`);
/// the score itself is a band/score, so the reserved verdict green is allowed ON THE SCORE ONLY
/// (rule 6 — never on the card chrome or the duration line).
public struct SleepCard: View {
    let durationSec: Double?, score: Double?, sourceMissing: Bool
    public init(durationSec: Double?, score: Double?, sourceMissing: Bool = false) {
        self.durationSec = durationSec; self.score = score; self.sourceMissing = sourceMissing
    }

    public var body: some View {
        Surface(level: 2, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(JIColor.sleep).frame(width: 8, height: 8)
                    Text("Sleep").font(.caption).foregroundStyle(JIColor.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(durationText).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(JIColor.text)
                        Text("duration").font(.caption2).foregroundStyle(JIColor.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scoreText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor)
                        Text("score").font(.caption2).foregroundStyle(JIColor.muted)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
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
    private var scoreColor: Color { sleepScoreColor(score: score, sourceMissing: sourceMissing) }
}

private func bandTone(for score: Double) -> VerdictTone {
    switch readinessBand(for: score) { case .go: .go; case .warn: .amber; case .danger: .red }
}

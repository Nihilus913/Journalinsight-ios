import SwiftUI
import JICore
import JIDesign

public struct VerdictHeroView: View {
    let verdict: VerdictParts, readiness: Double?, readinessMissing: Bool
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(verdict: VerdictParts, readiness: Double?, readinessMissing: Bool) { self.verdict = verdict; self.readiness = readiness; self.readinessMissing = readinessMissing }

    public var body: some View {
        Surface(level: 1, radius: JIRadius.hero, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verdict.word)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(JIColor.color(for: verdict.tone))
                    .opacity(revealed ? 1 : 0).offset(y: revealed ? 0 : 12)
                    .accessibilityAddTraits(.isHeader)
                Text(verdict.session).font(.body).foregroundStyle(JIColor.text)
                    .opacity(revealed ? 1 : 0)
                // Controller ruling 1: `readiness.map { revealed ? $0 : 0 }` — plain `revealed ? readiness : 0`
                // would coerce a genuinely nil score to a literal 0 ("No data yet" would flash "0" pre-reveal).
                // nil stays nil at every point in the reveal; only a real score counts up from 0.
                HStack { Spacer(); ReadinessArcGauge(score: readiness.map { revealed ? $0 : 0 }, sourceMissing: readinessMissing); Spacer() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { withAnimation(reduceMotion ? nil : JIMotion.reveal) { revealed = true } }
        .onDisappear { revealed = false }   // reveal fires on EVERY open/return (feel diagnosis 2026-09-03)
    }
}

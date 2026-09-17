import SwiftUI
import JICore
import JIDesign

public struct VerdictHeroView: View {
    let verdict: VerdictParts, readiness: Double?, readinessMissing: Bool
    let challengesModel: ChallengesViewModel?
    @State private var revealed = false
    @State private var showChallenges = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(verdict: VerdictParts, readiness: Double?, readinessMissing: Bool, challengesModel: ChallengesViewModel? = nil) {
        self.verdict = verdict; self.readiness = readiness; self.readinessMissing = readinessMissing
        self.challengesModel = challengesModel
    }

    public var body: some View {
        Surface(level: 1, radius: JIRadius.hero, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verdict.word)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(JIColor.color(for: verdict.tone))
                    .accessibilityAddTraits(.isHeader)
                    .jiReveal()
                Text(verdict.session).font(.body).foregroundStyle(JIColor.text)
                    .jiReveal()
                // Controller ruling 1: `readiness.map { revealed ? $0 : 0 }` — plain `revealed ? readiness : 0`
                // would coerce a genuinely nil score to a literal 0 ("No data yet" would flash "0" pre-reveal).
                // nil stays nil at every point in the reveal; only a real score counts up from 0.
                HStack { Spacer(); ReadinessArcGauge(score: readiness.map { revealed ? $0 : 0 }, sourceMissing: readinessMissing); Spacer() }
                // W3b-L3 — oracle `VerdictHero.tsx`'s challenges link (its own row opens
                // `app/challenges.tsx`). Only the link lives here; the gate-challenge summary/
                // mark-complete prompt it also renders is out of this lane's scope (this row's
                // job is just to reach `ChallengesView`).
                if let challengesModel {
                    Button {
                        showChallenges = true
                    } label: {
                        HStack {
                            Text("Gate challenge").font(.footnote.weight(.semibold)).foregroundStyle(JIColor.text)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(JIColor.muted)
                        }
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Gate challenge progress — open challenges")
                    // Attached locally so this row never needs the enclosing `NavigationStack`'s
                    // own `navigationDestination(for:)` (owned by App/RootTabView.swift, out of
                    // this lane's file list) — a plain isPresented push still lands on the same
                    // stack.
                    .navigationDestination(isPresented: $showChallenges) {
                        ChallengesView(model: challengesModel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { withAnimation(reduceMotion ? nil : JIMotion.reveal) { revealed = true } }
        .onDisappear { revealed = false }   // reveal fires on EVERY open/return (feel diagnosis 2026-09-03)
    }
}

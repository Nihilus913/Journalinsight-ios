import SwiftUI
import JICore
import JIDesign

public struct VerdictHeroView: View {
    let verdict: VerdictParts, readiness: Double?, readinessMissing: Bool
    let challengesModel: ChallengesViewModel?
    let gateRespondModel: GateRespondViewModel?   // W5b-L4: nil = no respond controls (same optional idiom as `challengesModel`)
    @State private var revealed = false
    @State private var showChallenges = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: the sweep renders this view outside a real window — a haptic fired from there
    /// enqueues an action with no update to attach it to and traps the test process.
    @Environment(\.jiOffscreenRender) private var offscreen
    public init(verdict: VerdictParts, readiness: Double?, readinessMissing: Bool, challengesModel: ChallengesViewModel? = nil, gateRespondModel: GateRespondViewModel? = nil) {
        self.verdict = verdict; self.readiness = readiness; self.readinessMissing = readinessMissing
        self.challengesModel = challengesModel; self.gateRespondModel = gateRespondModel
    }

    public var body: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verdict.word)
                    .jiNumeral(.numeralHero)
                    .foregroundStyle(theme.color(verdictColorRole(verdict.tone)))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("today.verdict.word")
                    .jiReveal()
                Text(verdict.session).jiFont(.body).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("today.verdict.session")
                    .jiReveal()
                // Controller ruling 1: `readiness.map { revealed ? $0 : 0 }` — plain `revealed ? readiness : 0`
                // would coerce a genuinely nil score to a literal 0 ("No data yet" would flash "0" pre-reveal).
                // nil stays nil at every point in the reveal; only a real score counts up from 0.
                // Label mirrors the RN oracle's ReadinessArcGauge (`Readiness ${rounded} — open
                // detail` / `Readiness — open detail`); nil score keeps the no-score wording.
                HStack { Spacer(); ReadinessArcGauge(score: readiness.map { (revealed || offscreen) ? $0 : 0 }, sourceMissing: readinessMissing); Spacer() }
                    .accessibilityLabel(readiness.map { "Readiness \(Int($0.rounded())) — open detail" } ?? "Readiness — open detail")
                    .accessibilityIdentifier("today.readinessGauge")
                // W3b-L3 — oracle `VerdictHero.tsx`'s challenges link (its own row opens
                // `app/challenges.tsx`). Only the link lives here; the gate-challenge summary/
                // mark-complete prompt it also renders is out of this lane's scope (this row's
                // job is just to reach `ChallengesView`).
                if let challengesModel {
                    Button {
                        showChallenges = true
                    } label: {
                        HStack {
                            Text("Gate challenge").jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(theme.color(.muted))
                        }
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Gate challenge progress — open challenges")
                    .accessibilityIdentifier("today.gateChallenge")
                    // Attached locally so this row never needs the enclosing `NavigationStack`'s
                    // own `navigationDestination(for:)` (owned by App/RootTabView.swift, out of
                    // this lane's file list) — a plain isPresented push still lands on the same
                    // stack.
                    .navigationDestination(isPresented: $showChallenges) {
                        ChallengesView(model: challengesModel)
                    }
                }
                if let gateRespondModel { GateRespondCard(model: gateRespondModel) }   // W5b-L4 (P-gate-respond) card mount — oracle VerdictHero.tsx mounts GateRespondCard + SessionFeelInput here
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gateRationaleDestination()   // W5b-L2 — oracle VerdictHero.tsx:404 (whole card → gate-rationale)
        .jiHapticVerdictReveal(verdict.tone, key: "\(verdict.word)|\(verdict.session)", trigger: revealed && !offscreen)   // W8-L1 (P-haptics) — oracle VerdictHero.tsx:184 hapticVerdictReveal(tone), once per verdict (verdictRevealed), never per tab return
        .onAppear { withAnimation(reduceMotion ? nil : JIMotion.reveal) { revealed = true } }
        .onDisappear { revealed = false }   // reveal fires on EVERY open/return (feel diagnosis 2026-09-03)
    }
}

/// B-33: the verdict tone → semantic role map (the theme-aware twin of the classic tone helper). The
/// reserved set is unchanged — go/amber/red/muted → go/reduced/danger/muted (rule 6).
public nonisolated func verdictColorRole(_ tone: VerdictTone) -> JIColorRole {
    switch tone { case .go: .go; case .amber: .reduced; case .red: .danger; case .muted: .muted }
}

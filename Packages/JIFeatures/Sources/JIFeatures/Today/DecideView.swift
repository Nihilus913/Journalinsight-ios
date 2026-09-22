import SwiftUI
import JICore
import JIDesign

/// B-57 §2 Decide — which actions are live. Syncing (no verdict yet) disables both; a rest day
/// has Go only.
public nonisolated func decideActions(verdict: VerdictParts, syncing: Bool) -> (go: Bool, adjust: Bool) {
    if syncing { return (false, false) }
    return (true, !TodayMorningFlow.isRestDay(verdict))
}

/// B-57 §2 Decide: the verdict word + session, large, ONE readiness ring behind it, Go / Adjust.
/// Go answers the gate through the existing Outbox-first `GateRespondViewModel.respond(choice: .yes)`
/// and advances only once `responded` is true (a `.queued` answer counts; `.failed` never does).
public struct DecideView: View {
    let verdict: VerdictParts
    let readiness: Double?
    let syncing: Bool
    let gateRespondModel: GateRespondViewModel?
    let onAdvance: () -> Void
    @State private var showAdjust = false
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(verdict: VerdictParts, readiness: Double?, syncing: Bool,
                gateRespondModel: GateRespondViewModel?, onAdvance: @escaping () -> Void) {
        self.verdict = verdict; self.readiness = readiness; self.syncing = syncing
        self.gateRespondModel = gateRespondModel; self.onAdvance = onAdvance
    }

    public var body: some View {
        let actions = decideActions(verdict: verdict, syncing: syncing)
        let showsAdjust = actions.adjust && gateRespondModel != nil && gateRespondModel?.recommendation != .insufficientData
        Surface(level: 1, padding: 24) {
            VStack(spacing: 20) {
                ZStack {
                    // Rule 5: a missing readiness is a muted ring with "—", never a zero-filled score ring.
                    ScoreRing(value: readiness ?? 0, max: 100,
                              tint: readiness == nil ? theme.color(.nested) : theme.color(verdictColorRole(verdict.tone)), size: 160)
                    VStack(spacing: 4) {
                        Text(syncing ? "Syncing…" : verdict.word)
                            .jiNumeral(.numeralHero)
                            .foregroundStyle(theme.color(syncing ? .muted : verdictColorRole(verdict.tone)))
                            .lineLimit(1).minimumScaleFactor(0.4)
                            .padding(.horizontal, 12)
                        if !syncing {
                            Text(readiness.map(todayRingValueText) ?? "—").jiFont(.caption).foregroundStyle(theme.color(.muted))
                        }
                    }
                    .frame(width: 150)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heroRingAccessibilityLabel(label: "Readiness", value: readiness))
                .accessibilityIdentifier("today.readinessGauge")
                if !syncing, !verdict.session.isEmpty {
                    Text(verdict.session).jiFont(.cardTitle, weight: .semibold).foregroundStyle(theme.color(.text))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("today.verdict.session")
                }
                HStack(spacing: 12) {
                    Button("Go") { go() }
                        .buttonStyle(.borderedProminent).tint(theme.color(.go))
                        .disabled(!actions.go || gateRespondModel?.phase == .submitting)
                        .accessibilityIdentifier("today.decide.go")
                    if showsAdjust {
                        Button("Adjust") { showAdjust = true }
                            .buttonStyle(.bordered)
                            .disabled(gateRespondModel?.phase == .submitting)
                            .accessibilityIdentifier("today.decide.adjust")
                    }
                }
                .controlSize(.large)
                if let message = gateRespondModel?.errorMessage {
                    Text(message).jiFont(.caption).foregroundStyle(theme.color(.danger))
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("today.decide.error")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showAdjust) {
            if let gateRespondModel {
                NavigationStack {
                    ScrollView {
                        GateRespondCard(model: gateRespondModel, showsFeelRow: false)
                            .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .background(theme.color(.bg))
                    .navigationTitle("Adjust")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showAdjust = false }
                                .accessibilityIdentifier("today.gateRespond.done")
                        }
                    }
                }
                .jiTheme(theme)
                .presentationDetents([.medium, .large])
            }
        }
        // Advance only when the answer actually settled (`.logged` or `.queued`) — never on `.failed`.
        .onChange(of: gateRespondModel?.responded ?? false) { _, responded in
            if responded { showAdjust = false; advance() }
        }
    }

    private func go() {
        guard let gateRespondModel, gateRespondModel.recommendation != .insufficientData else { advance(); return }
        // Already answered (e.g. via the hero before B-57, or a relaunch mid-flow): just move on.
        if gateRespondModel.responded { advance(); return }
        Task { _ = await gateRespondModel.respond(choice: .yes) }   // onChange(responded) advances
    }

    private func advance() {
        if !offscreen { JIHaptic.fire(.saveSuccess) }
        onAdvance()
    }
}

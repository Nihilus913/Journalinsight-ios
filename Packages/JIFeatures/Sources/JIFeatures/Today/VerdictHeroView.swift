import SwiftUI
import JICore
import JIDesign

/// B-42 (W-B46 L2) — the Today hero, redesigned after Bevel Home and Apple Fitness Summary
/// (`docs/design/references/2026-09-22-{bevel-home,apple-fitness-summary}.png`, scout
/// `docs/waves/scouts/B-42-scout.md` §5–§6):
///
///   * a **ring trio** (Readiness · Sleep · Load) replaces the single hero arc — Bevel's
///     Strain/Recovery/Sleep card, in our metrics, value inside each ring and the label under it;
///   * the giant verdict WORD is demoted to the tinted **lead of the insight sentence**
///     (`InsightSentence`, the `buildInsight` port) — Bevel's narrative card, not a billboard;
///   * the respond controls move OUT of the card into a medium-detent sheet behind ONE compact
///     action row, so the KPI row and the Trends card clear the fold at 393 × 852 (scout §5, the
///     defect Toby reported on the device).
///
/// Accessibility identifiers `today.verdict.*` and `today.feel.N` are kept verbatim — tests and
/// the sim smoke address them.
public struct VerdictHeroView: View {
    let verdict: VerdictParts
    let readiness: Double?, readinessMissing: Bool
    /// The other two rings of the trio. `nil` renders the ring's empty state, never a zero (rule 5).
    let sleepScore: Double?, load: Double?
    /// The `buildInsight` sentence for today. Empty falls back to the verdict's own summary.
    let insight: String
    let gateRespondModel: GateRespondViewModel?   // W5b-L4: nil = no respond controls
    /// B-57 §6: the Day face drops the "Respond ›" / logged one-liner (Decide owns the answer);
    /// the feel segment stays either way.
    let showsRespondRow: Bool
    @State private var revealed = false
    @State private var showRespond = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: the sweep renders this view outside a real window — a haptic fired from there
    /// enqueues an action with no update to attach it to and traps the test process.
    @Environment(\.jiOffscreenRender) private var offscreen
    /// §8.1 "reflows, never clips": `ScoreRing` scales with the type size, so three 76 pt rings
    /// side by side overflow 393 pt at AX sizes — the trio stacks there instead.
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(verdict: VerdictParts, readiness: Double?, readinessMissing: Bool,
                sleepScore: Double? = nil, load: Double? = nil, insight: String = "",
                gateRespondModel: GateRespondViewModel? = nil,
                showsRespondRow: Bool = true) {
        self.verdict = verdict; self.readiness = readiness; self.readinessMissing = readinessMissing
        self.sleepScore = sleepScore; self.load = load; self.insight = insight
        self.gateRespondModel = gateRespondModel
        self.showsRespondRow = showsRespondRow
    }

    private var line: (lead: String, rest: String) {
        // W-FIX1 BUG-27: the tinted lead is the user word (Full / Modified / Rest).
        insightLine(word: verdictUserWord(verdict), sentence: insight.isEmpty ? verdict.session : insight)
    }

    public var body: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                ringTrio
                insightSentence
                if let gateRespondModel { actionRow(gateRespondModel) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gateRationaleDestination()   // W5b-L2 — oracle VerdictHero.tsx:404 (whole card → gate-rationale)
        .jiHapticVerdictReveal(verdict.tone, key: "\(verdict.word)|\(verdict.session)", trigger: revealed && !offscreen)   // W8-L1 (P-haptics) — oracle VerdictHero.tsx:184 hapticVerdictReveal(tone), once per verdict (verdictRevealed), never per tab return
        .onAppear { withAnimation(reduceMotion ? nil : JIMotion.reveal) { revealed = true } }
        .onDisappear { revealed = false }   // reveal fires on EVERY open/return (feel diagnosis 2026-09-03)
    }

    // MARK: - Ring trio (spec §4b exception: the trio replaces the single hero arc)

    @ViewBuilder private var ringTrio: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        layout {
            heroRing(label: "Readiness", value: readiness, max: 100, tint: theme.color(.go), missing: readinessMissing, identifier: "today.readinessGauge")
            if !stacked { trioDivider }
            heroRing(label: "Sleep", value: sleepScore, max: 100, tint: theme.color(.sleep), missing: false, identifier: "today.hero.sleep")
            if !stacked { trioDivider }
            // Load = ACWR, a 0–2 band where 1.0 is "carrying last month's load"; the ring is that
            // band, not a 0–100 score.
            heroRing(label: "Load", value: load, max: 2, tint: theme.color(.reduced), missing: false, decimals: 2, identifier: "today.hero.load")
        }
        .frame(maxWidth: .infinity)
    }

    private var trioDivider: some View {
        Rectangle().fill(theme.color(.hairlineNested)).frame(width: 1, height: 64)
    }

    @ViewBuilder
    private func heroRing(label: String, value: Double?, max: Double, tint: Color, missing: Bool, decimals: Int = 0, identifier: String) -> some View {
        let shown: Double? = missing ? nil : value
        VStack(spacing: 8) {
            ZStack {
                // `shown.map { revealed ? $0 : 0 }` (controller ruling 1): a genuinely missing
                // score stays nil at every point of the reveal — only a real one counts up.
                ScoreRing(value: shown.map { (revealed || offscreen) ? $0 : 0 } ?? 0,
                          max: max,
                          tint: shown == nil ? theme.color(.nested) : tint,
                          size: 76)
                Text(shown.map { $0.formatted(.number.precision(.fractionLength(decimals))) } ?? "—")
                    .jiNumeral(.numeralCompact)
                    .foregroundStyle(shown == nil ? theme.color(.muted) : theme.color(.text))
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            // B-47: Bevel sets its Strain/Recovery/Sleep labels in primary text at body size —
            // a muted 13 pt label under a 76 pt ring is what read as "cheap".
            Text(label).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroRingAccessibilityLabel(label: label, value: shown, decimals: decimals))
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Insight sentence (the verdict word, demoted to its tinted lead)

    /// The session line is only its own row when it would say something new: the insight
    /// sentence's fallback tier already ends in the session ("GO — full session."), and two copies
    /// of the same phrase is what made the old hero feel like a billboard. `today.verdict.session`
    /// stays addressable either way — it moves up to the group when the row is folded in.
    private var showsSessionRow: Bool { !verdict.session.isEmpty && !line.rest.contains(verdict.session) }

    @ViewBuilder private var insightSentence: some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(line.lead).foregroundStyle(theme.color(verdictColorRole(verdict.tone))).fontWeight(.bold)
             + Text(line.rest).foregroundStyle(theme.color(.text)))
                .jiFont(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.verdict.word")
                .jiReveal()
            if showsSessionRow {
                Text(verdict.session).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .accessibilityIdentifier("today.verdict.session")
                    .jiReveal()
            }
        }
        .accessibilityIdentifier(showsSessionRow ? "today.verdict.group" : "today.verdict.session")
    }

    // MARK: - The one compact action row

    /// Scout §5(i): ONE row — "Respond ›" (or the logged one-liner once answered) plus the 1–5 feel
    /// segment. Everything else the oracle rendered inline lives in the sheet.
    @ViewBuilder
    private func actionRow(_ model: GateRespondViewModel) -> some View {
        if model.recommendation != .insufficientData {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.color(.hairlineNested))
                if showsRespondRow, model.responded {
                    GateRespondedRow(model: model)
                } else if showsRespondRow {
                    Button { showRespond = true } label: {
                        HStack(spacing: 4) {
                            Text("Respond").jiFont(.footnote, weight: .semibold)
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(theme.color(.info))
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Respond to this recommendation")
                    .accessibilityIdentifier("today.gateRespond.open")
                }
                feelSegment(model)
            }
            .sheet(isPresented: $showRespond) {
                NavigationStack {
                    ScrollView {
                        // The card's own feel row is suppressed: this hero already shows it, and
                        // `today.feel.N` must stay unambiguous.
                        GateRespondCard(model: model, showsFeelRow: false)
                            .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .background(theme.color(.bg))
                    .navigationTitle("Respond")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showRespond = false }
                                .accessibilityIdentifier("today.gateRespond.done")
                        }
                    }
                }
                .jiTheme(theme)
                .presentationDetents([.medium, .large])
            }
            // The sheet closes itself the moment the answer lands, so the hero returns to the
            // one-liner without a second tap (oracle: the card collapsed in place).
            .onChange(of: model.responded) { _, responded in if responded { showRespond = false } }
        }
    }

    @ViewBuilder
    private func feelSegment(_ model: GateRespondViewModel) -> some View {
        HStack(spacing: 8) {
            Text("Felt").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
            ForEach(1...5, id: \.self) { score in
                let selected = model.feelScore == score
                Button("\(score)") { Task { await model.logFeel(score: score) } }
                    .buttonStyle(.pressableScale)
                    .disabled(model.feelPhase == .submitting)
                    .frame(width: 32, height: 32)
                    .background(selected ? theme.color(.info) : theme.color(.control), in: Circle())
                    .foregroundStyle(selected ? theme.color(.bg) : theme.color(.text))
                    .font(.caption.bold())
                    .accessibilityLabel("Feel \(score)")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                    .accessibilityIdentifier("today.feel.\(score)")
            }
            Spacer(minLength: 0)
            if let message = model.feelErrorMessage {
                Text(message).jiFont(.caption).foregroundStyle(theme.color(.danger))
                    .lineLimit(1)
                    .accessibilityIdentifier("today.feel.error")
            } else if let score = model.feelScore, model.feelPhase == .logged || model.feelPhase == .queued {
                Text("\(score)/5").jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.info))
                    .accessibilityIdentifier("today.feel.logged")
            }
        }
        .frame(minHeight: 44)
    }
}

/// B-33: the verdict tone → semantic role map (the theme-aware twin of the classic tone helper). The
/// reserved set is unchanged — go/amber/red/muted → go/reduced/danger/muted (rule 6).
public nonisolated func verdictColorRole(_ tone: VerdictTone) -> JIColorRole {
    switch tone { case .go: .go; case .amber: .reduced; case .red: .danger; case .muted: .muted }
}

/// B-42: splits the hero line into its tinted lead (the verdict word) and the rest of the insight
/// sentence. The sentence's own "Verdict: GO — …" / "Verdict is REDUCED …" opening is stripped, so
/// the word is said once, not twice; the em-dash join is dropped when the remainder opens with its
/// own parenthetical. An empty sentence leaves the lead standing alone.
public nonisolated func insightLine(word: String, sentence: String) -> (lead: String, rest: String) {
    var rest = sentence.trimmingCharacters(in: .whitespaces)
    for prefix in ["Verdict is ", "Verdict: "] where rest.hasPrefix(prefix) {
        rest = String(rest.dropFirst(prefix.count))
        break
    }
    if rest.hasPrefix(word) { rest = String(rest.dropFirst(word.count)) }
    rest = rest.trimmingCharacters(in: .whitespaces)
    while rest.hasPrefix("—") || rest.hasPrefix("-") {
        rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    if rest.isEmpty { return (word, "") }
    return (word, rest.hasPrefix("(") ? " \(rest)" : " — \(rest)")
}

/// VoiceOver copy for one hero ring — pure, so it is asserted without a view harness.
public nonisolated func heroRingAccessibilityLabel(label: String, value: Double?, decimals: Int = 0) -> String {
    guard let value else { return "\(label), no data yet" }
    return "\(label) \(value.formatted(.number.precision(.fractionLength(decimals))))"
}

import SwiftUI
import JICore
import JICompute
import JIDesign

/// B-57 §2 Decide — which actions are live. Syncing (no verdict yet) disables both; a rest day
/// has Go only.
public nonisolated func decideActions(verdict: VerdictParts, syncing: Bool) -> (go: Bool, adjust: Bool) {
    if syncing { return (false, false) }
    return (true, !TodayMorningFlow.isRestDay(verdict))
}

// MARK: - W-B57b (B-62) effective verdict helpers

/// The override that applies to `verdictDate` — one for another date (a stale queue, yesterday's
/// row) never changes what today shows.
public nonisolated func overrideForVerdictDate(_ o: VerdictOverride?, verdictDate: String?) -> VerdictOverride? {
    guard let o, let verdictDate, o.date == verdictDate else { return nil }
    return o
}

/// `effectiveVerdict` + `effectiveVerdictTone` folded into a `VerdictParts`, so every existing
/// verdict view (Decide, the Day hero, the summary line) shows the user's call unchanged.
public nonisolated func effectiveVerdictParts(parts: VerdictParts, override: VerdictOverride?) -> VerdictParts {
    guard override != nil else { return displayVerdictParts(parts) }
    let e = effectiveVerdict(parts: parts, override: override)
    var out = parts
    out.word = e.word
    out.session = e.session
    out.tone = effectiveVerdictTone(parts: parts, override: override)
    return out
}

/// The verdict's own reason — RN's parenthetical ("MODIFIED (HRV low)" → "HRV low") — shown on
/// Decide when the hub sent no gate signals (a verdict written before migration 048).
public nonisolated func verdictReasonLine(_ parts: VerdictParts) -> String? {
    // W-FIX1 BUG-03: "(auto-regulated)" is not a reason — Decide shows the trimmed prescription.
    guard !isAutoRegulated(parts) else { return nil }
    guard let open = parts.word.firstIndex(of: "("), let close = parts.word.lastIndex(of: ")"), open < close else { return nil }
    let inner = parts.word[parts.word.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
    return inner.isEmpty ? nil : inner
}

/// W-FIX10 R-05: the hub's reason while the morning push is held for the watch
/// (`morning_go.py` `WAITING_FOR_WATCH_REASON`, written to `plan.morning_verdict.reason`); nil for
/// any other reason.
public nonisolated func decideHeldReason(_ reason: String?) -> String? {
    guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
          reason.hasPrefix("Waiting for the watch") else { return nil }
    return reason
}

/// The one human "why" line under Decide's verdict.
public nonisolated enum DecideWhyLine: Equatable, Sendable {
    /// The push is held: the overnight data is not in yet (shown even with gate signals).
    case held(String)
    /// The hub's reduced prescription on an amber day.
    case prescription(String)
    /// The verdict's own reason (a pre-048 verdict, no gate signals).
    case reason(String)
}

public nonisolated func decideWhyLine(verdict: VerdictParts, override: VerdictOverride?, hasGateSignals: Bool,
                                      heldReason: String?, week: PlanWeekOut? = nil) -> DecideWhyLine? {
    if override == nil, let held = decideHeldReason(heldReason) { return .held(held) }
    if let prescription = decidePrescriptionLine(verdict: verdict, override: override, week: week) { return .prescription(prescription) }
    if !hasGateSignals, let reason = verdictReasonLine(verdict) { return .reason(reason) }
    return nil
}

/// One row of the Adjust sheet's choice picker.
public nonisolated struct AdjustChoice: Equatable, Sendable, Identifiable {
    public let choice: VerdictOverrideChoice
    public let title: String
    public let session: String
    public var id: String { choice.rawValue }
}

/// Adjust = "my call": the full session / the modified session / rest. Session texts follow the
/// hub's resolution (`localOverrideSession`) so the picker says what will actually be written.
public nonisolated func adjustChoices(parts: VerdictParts, sessionForToday: String?) -> [AdjustChoice] {
    [
        AdjustChoice(choice: .full, title: "Full session",
                     session: localOverrideSession(choice: .full, parts: parts, sessionForToday: sessionForToday)),
        AdjustChoice(choice: .modified, title: "Modified session",
                     session: localOverrideSession(choice: .modified, parts: parts, sessionForToday: sessionForToday)),
        AdjustChoice(choice: .rest, title: "Rest",
                     session: localOverrideSession(choice: .rest, parts: parts, sessionForToday: sessionForToday)),
    ]
}

/// Go / Adjust's single write path: the verdict override (Outbox-first inside the model), never
/// the weekly gate's `respondGate`. `true` = settled (`.logged` or `.queued`).
@MainActor
public func decideSubmit(model: VerdictOverrideViewModel, date: String, choice: VerdictOverrideChoice, reason: String,
                         parts: VerdictParts, sessionForToday: String?) async -> Bool {
    await model.setOverride(date: date, choice: choice, reason: reason,
                            optimisticSession: localOverrideSession(choice: choice, parts: parts, sessionForToday: sessionForToday))
}

/// W-FIX11 H1-01 (S1): what Go writes. With a call already on screen for the verdict date (the
/// user's Adjust, or an earlier Go) Go confirms THAT call — nothing is written (nil), so the hub's
/// row stays the user's; only with no call yet does Go accept the hub verdict.
public nonisolated func decideGoChoice(override: VerdictOverride?) -> VerdictOverrideChoice? {
    override == nil ? .accept : nil
}

/// Go's write path (`decideGoChoice`). `true` = a write settled (Decide advances on `settled`);
/// `false` with no write made = the shown call is kept and the caller advances itself.
@MainActor
public func decideGo(model: VerdictOverrideViewModel, date: String, override: VerdictOverride?,
                     parts: VerdictParts, sessionForToday: String?) async -> Bool {
    guard let choice = decideGoChoice(override: override) else { return false }
    return await decideSubmit(model: model, date: date, choice: choice, reason: "", parts: parts, sessionForToday: sessionForToday)
}

/// Decide's big word: the user-facing word (`verdictUserWord` — "GO" → "Full", "MODIFIED (HRV low)"
/// → "Modified"), without RN's parenthetical, which never fits; the reason is carried by the Why
/// rows (or the reason line when there are none).
public nonisolated func decideWord(_ parts: VerdictParts) -> String { verdictUserWord(parts) }

/// W-FIX6 F6-11 (S1): the ONE headline of the morning call — the word, session and tone Decide
/// shows, and the very same strings the widgets and the Live Activity carry (they used to show the
/// hub's raw "GO (auto-regulated)" in green beside Decide's amber "Modified").
public nonisolated struct VerdictHeadline: Equatable, Sendable {
    public let word: String, session: String
    public let tone: VerdictTone
}

/// `override` must already be the one for the verdict's date (`overrideForVerdictDate`).
/// No verdict = "—" + "No verdict yet" (never a guessed call).
public nonisolated func verdictHeadline(parts: VerdictParts, override: VerdictOverride?) -> VerdictHeadline {
    guard parts.tone != .muted || override != nil else { return VerdictHeadline(word: "—", session: parts.session, tone: .muted) }
    let shown = effectiveVerdictParts(parts: parts, override: override)
    return VerdictHeadline(word: decideWord(shown), session: shown.session, tone: shown.tone)
}

/// W-FIX6 F6-11: the hero's kicker. A call from another day (a cache, or the hub's `is_stale`
/// before morning_go ran) is never "your call for today" — it names its own day.
public nonisolated func decideCallHeader(verdictDate: String?, isStale: Bool?, today: String) -> String {
    guard let verdictDate, verdictDate != today || isStale == true else { return "YOUR CALL FOR TODAY" }
    let parse = DateFormatter()
    parse.calendar = Calendar(identifier: .gregorian); parse.locale = Locale(identifier: "en_US_POSIX")
    parse.timeZone = TimeZone(identifier: "UTC"); parse.dateFormat = "yyyy-MM-dd"
    guard let d = parse.date(from: String(verdictDate.prefix(10))) else { return "LAST CALL" }
    let out = DateFormatter()
    out.calendar = parse.calendar; out.locale = parse.locale; out.timeZone = parse.timeZone
    out.dateFormat = "EEE, MMM d"
    return "LAST CALL · " + out.string(from: d).uppercased()
}

/// B-57 W1 Decide "Session" row. The hub sends no session time or exercise list to Today, so W1
/// shows the session name only (time, exercises and first working weight: W5 progression).
/// W-FIX1 BUG-03: the line under Decide's session on an amber (auto-regulated) day — the hub's
/// reduced prescription, so "Modified" says what changed. nil on every other verdict and once the
/// user made another call (full / modified / rest).
/// W-SSOT-2 S2-3: `week` = the served `/planning/week` (`TodayViewModel.planWeek`) — it names the
/// session's kind first, so the hero verdict trims the same session the week shows.
public nonisolated func decidePrescriptionLine(verdict: VerdictParts, override: VerdictOverride?,
                                               week: PlanWeekOut? = nil) -> String? {
    if let override, override.choice != .accept { return nil }
    return autoRegulatedPrescription(verdict, week: week)
}

/// W-FIX1 BUG-17: Decide's "Today's session" row links to Day (spec §2 L2) — live whenever the
/// verdict is in (while syncing there is no Day to show yet).
public nonisolated func decideSessionRowOpensDay(syncing: Bool) -> Bool { !syncing }

public nonisolated func decideSessionRowText(sessionForToday: String?, verdict: VerdictParts) -> (title: String, detail: String) {
    let name = [sessionForToday, verdict.session].compactMap { $0 }.first { !$0.isEmpty }
    return ("Today's session", name ?? "— \(JIMissingReason.noData.rawValue)")
}

/// W-FIX5 W5-3: the session row's lift weight — never beside a Rest call (the hub's REST word, the
/// user's "Rest" override, or a row whose session reads "Rest"): there is nothing to lift today.
public nonisolated func decideSessionLiftShown(verdict: VerdictParts, sessionDetail: String,
                                               lifts: [LiftProgression]) -> (kg: String, caption: String?)? {
    if TodayMorningFlow.isRestDay(verdict) { return nil }
    let session = sessionDetail.trimmingCharacters(in: .whitespaces).lowercased()
    if session.hasPrefix("rest") { return nil }
    // W-FIX6 fixer (F6-11 detail): a cardio session (Long Z2, intervals, a run) has nothing to
    // lift either — the weight shows only beside a session that names a lift.
    guard decideSessionLiftKeywords.contains(where: { session.contains($0) }) else { return nil }
    return decideSessionLift(lifts)
}

/// The words that make a session a lifting session ("Day 1 Full Upper + Z2 40min", "Strength").
nonisolated let decideSessionLiftKeywords = ["upper", "lower", "full body", "strength", "lift"]

/// W-FIX5 W5-3: at accessibility sizes the session row stacks (title, session, weight) instead of
/// squeezing three texts into one line and clipping them.
public nonisolated func decideSessionRowStacked(_ size: DynamicTypeSize) -> Bool { size.isAccessibilitySize }

/// W-FIX4 PF-01: in the app Go / Adjust are pinned to the bottom of Decide, above the floating tab
/// bar (the screens live in a layer behind the chrome-only `TabView`, so the bar is not in their
/// safe area); the sweep (`jiOffscreenRender`) keeps them inline at the end of the card.
public nonisolated func decideActionsPinned(offscreen: Bool) -> Bool { !offscreen }

/// W-FIX4 PF-01: the room the pinned Go / Adjust bar keeps under itself for the floating tab bar.
public nonisolated func decideActionBarBottomClearance(_ width: JIWidthClass) -> CGFloat { tabBarBottomClearance(width) }

/// W-FIX3 BUG-30 (board 01): Go's label is black on the green verdict button.
public nonisolated let decideGoForeground = Color.black

// MARK: - W-GUI T1 (mockups 01 / 10)

/// The hero card's tint: the verdict's own role (go / amber / red); none while syncing.
public nonisolated func decideHeroTintRole(tone: VerdictTone, syncing: Bool) -> JIColorRole? {
    syncing ? nil : verdictColorRole(tone)
}

/// The readiness ring's caption. The score is not on the hub yet (plan §B: W3) — the ring shows
/// "—" with the honest reason and the count of overnight nights already on the phone; with a
/// score it is just the word.
/// W-B57-W3 fixer: with no Garmin readiness the ring carries the recovery score (the gate's own
/// inputs) and its own calibration count — never "7 of 7 so far · Calibrating" beside a score.
/// W-FIX6 F6-11: never "n of n so far · Calibrating" — once the count is met it is dropped (the
/// remaining reason is the score's own, not the night count).
public nonisolated func decideReadinessCaption(score: Double?, nights: Int?, recovery: RecoveryScoreResult? = nil,
                                               hubRecovery: Double? = nil) -> String {
    if let score {
        if let hubRecovery, hubRecovery == score {
            return hubRecovery < Double(RecoveryScore.lowScore) ? "Recovery low" : "Recovery"
        }
        guard let recovery, recovery.status == .ok, let s = recovery.score, Double(s) == score else { return "Readiness" }
        return s < RecoveryScore.lowScore ? "Recovery low" : "Recovery"
    }
    if let recovery {
        switch recovery.status {
        case .calibrating:
            let need = recovery.nightsNeeded
            let n = max(recovery.nights, 0)
            guard n < need else { return "Recovery · \(JIMissingReason.calibrating.rawValue)" }
            return "Recovery needs \(need) nights · \(n) of \(need) so far · \(JIMissingReason.calibrating.rawValue)"
        case .missing, .ok:
            return "Recovery · \(JIMissingReason.noData.rawValue)"
        }
    }
    let n = max(nights ?? 0, 0)
    guard n < 7 else { return "Readiness · \(JIMissingReason.noData.rawValue)" }
    return "Readiness needs 7 overnight nights · \(n) of 7 so far · \(JIMissingReason.calibrating.rawValue)"
}

/// W-FIX6 F6-11: the hub's own recovery score for the call (`gate_signals` key `recovery`), nil when
/// the hub did not send one.
public nonisolated func decideHubRecovery(_ signals: [GateSignal]?) -> Double? {
    signals?.first { $0.key == "recovery" }?.value
}

/// W-B57-W3 fixer: the ring's number — the hub's readiness when present, then (W-FIX6 F6-11) the
/// hub's recovery score for the call, else the on-device recovery score.
public nonisolated func decideRingScore(readiness: Double?, recovery: RecoveryScoreResult?, hubRecovery: Double? = nil) -> Double? {
    if let readiness { return readiness }
    if let hubRecovery { return hubRecovery }
    guard let recovery, recovery.status == .ok, let s = recovery.score else { return nil }
    return Double(s)
}

/// Report §7: ONE primary button per screen. Go is the primary; Adjust is secondary; a rest day
/// (no Adjust) still has exactly one.
public nonisolated enum DecideButtonRole: Sendable, Equatable { case primary, secondary }
public nonisolated func decideButtonRoles(showsAdjust: Bool) -> [DecideButtonRole] {
    showsAdjust ? [.primary, .secondary] : [.primary]
}

/// The one RMSSD / SDNN footnote (mockups 01 / 10), shown once under the signals.
public nonisolated let decideHrvFootnote = "HRV here is overnight RMSSD from the Watch. The Health app's daytime HRV is SDNN, a different calculation; the two are not comparable."

public extension EnvironmentValues {
    /// W-GUI T1: the "How the morning call works" row's destination (mockup 01), set by the
    /// app's gate wiring like `gateRationaleModel`; `nil` leaves the row inert.
    @Entry var gateConfigModel: GateConfigViewModel? = nil
}

// MARK: - View

/// B-57 §2 + §9 Decide (W1 board): date + synced pill, the (effective) verdict word + session, the
/// "Why" signal rows, today's session row, then Go / Adjust. Both write a verdict override for `verdictDate`
/// and advance only once the write settled (`.logged` / `.queued`), never on `.failed`.
public struct DecideView: View {
    let verdict: VerdictParts
    let readiness: Double?
    let syncing: Bool
    let gateSignals: [GateSignal]?
    let verdictDate: String?
    let sessionForToday: String?
    /// The override already known for `verdictDate` (hub `/morning` or this device's last write).
    let override: VerdictOverride?
    let overrideModel: VerdictOverrideViewModel?
    /// W-FIX3 C-f: the Day pill's time — the newer of the hub's sync and this app's last HealthKit
    /// upload (`TodayViewModel.syncedAt`), never the moment the screen fetched.
    let syncedAt: Date?
    /// Normals per gate-signal key for the Why rows (`decideSignalNormals`); empty = calibrating.
    let normals: [String: ClosedRange<Double>]
    /// Drawn above the card (Today's staleness banner); nil = none.
    let banner: StalenessBanner?
    let now: Date
    let onAdvance: () -> Void
    /// W-GUI T1: overnight nights already on the phone (the readiness ring's "n of 7"); nil = unknown.
    let calibrationNights: Int?
    /// W-FIX6 F6-11: the hub's `is_stale` for this call (nil = not sent).
    let isStale: Bool?
    /// W-FIX10 R-05: the hub's "Waiting for the watch…" reason while the push is held (nil = not held).
    let heldReason: String?
    /// W-SSOT-2 S2-3: the served `/planning/week` (`TodayViewModel.planWeek`); nil = not served.
    let planWeek: PlanWeekOut?
    @State private var showAdjust = false
    @State private var showGateConfig = false
    @Environment(\.gateConfigModel) private var gateConfigModel
    @Environment(\.recoveryInsight) private var recoveryInsight
    /// B-57 W5 C4: the session row's next working weight (nil in previews → not shown).
    @Environment(\.progression) private var progression
    @Environment(\.trainingWeekSummary) private var week
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiOffscreenRender) private var offscreen
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(verdict: VerdictParts, readiness: Double?, syncing: Bool, gateSignals: [GateSignal]?,
                verdictDate: String?, sessionForToday: String?, override: VerdictOverride?,
                overrideModel: VerdictOverrideViewModel?, syncedAt: Date?, normals: [String: ClosedRange<Double>] = [:],
                banner: StalenessBanner? = nil, now: Date = Date(), calibrationNights: Int? = nil, isStale: Bool? = nil,
                heldReason: String? = nil, planWeek: PlanWeekOut? = nil, onAdvance: @escaping () -> Void) {
        self.verdict = verdict; self.readiness = readiness; self.syncing = syncing
        self.gateSignals = gateSignals; self.verdictDate = verdictDate; self.sessionForToday = sessionForToday
        self.override = override; self.overrideModel = overrideModel
        self.syncedAt = syncedAt; self.normals = normals; self.banner = banner; self.now = now; self.onAdvance = onAdvance
        self.calibrationNights = calibrationNights; self.isStale = isStale; self.heldReason = heldReason
        self.planWeek = planWeek
    }

    private var shown: VerdictParts { effectiveVerdictParts(parts: verdict, override: override) }
    private var wasCaption: String? { override == nil ? nil : effectiveVerdict(parts: verdict, override: override).wasCaption }
    private var submitting: Bool { overrideModel?.phase == .submitting }

    /// The session row's label (W-FIX5 W5-3 stacking; W-FIX7 F7-1 the Apple Health status line).
    @ViewBuilder
    private func sessionRowLabel(_ row: (title: String, detail: String), lift: (kg: String, caption: String?)?,
                                 completion: SessionCompletion) -> some View {
        if decideSessionRowStacked(typeSize) {
            VStack(alignment: .leading, spacing: JISpacing.s1) {
                JIChevronRowLabel(title: row.title, systemImage: "dumbbell")
                Text(row.detail).jiFont(.subheadline).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                if let lift { sessionLiftText(lift, alignment: .leading) }
                SessionCompletionLine(completion: completion)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if completion.statusText != nil {
            VStack(alignment: .leading, spacing: JISpacing.s1) {
                HStack(spacing: JISpacing.s2) {
                    JIChevronRowLabel(title: row.title, value: row.detail, systemImage: "dumbbell")
                    if let lift { sessionLiftText(lift, alignment: .trailing).fixedSize() }
                }
                SessionCompletionLine(completion: completion)
                    .padding(.leading, JIChevronRowMetrics.iconWell + JISpacing.s3)
            }
        } else {
            JIChevronRowLabel(title: row.title, value: row.detail, systemImage: "dumbbell")
            if let lift { sessionLiftText(lift, alignment: .trailing).fixedSize() }
        }
    }

    /// B-57 W5 C4: the first lift's next weight, "↑ Bench up" under it when due.
    private func sessionLiftText(_ lift: (kg: String, caption: String?), alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(lift.kg).jiFont(.subheadline, weight: .bold).monospacedDigit()
                .foregroundStyle(theme.color(lift.caption == nil ? .text : .go))
            if let caption = lift.caption {
                Text(caption).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.go))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("today.decide.lift")
    }

    @ViewBuilder
    private func decideButtons(actions: (go: Bool, adjust: Bool), showsAdjust: Bool, stacked: Bool) -> some View {
        // W-FIX3 BUG-30 (board 01): black "Go" on the green button, never white.
        // W-GUI F9 (report §4.5): the ONE primary button — accent fill, black label (BUG-30 kept).
        Button { go() } label: { Text("Go").foregroundStyle(decideGoForeground).lineLimit(1).fixedSize().frame(maxWidth: .infinity) }
            .buttonStyle(.jiPrimary)
            .disabled(!actions.go || submitting)
            .accessibilityIdentifier("today.decide.go")
        if showsAdjust {
            Button { showAdjust = true } label: {
                Text("Adjust").lineLimit(1).fixedSize().frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(.jiSecondary)
            .disabled(submitting)
            .accessibilityIdentifier("today.decide.adjust")
        }
    }

    /// Go / Adjust (side by side while both labels fit whole, else stacked full-width — no
    /// "Ad-just" hyphenation at AX3) and the write's error line.
    @ViewBuilder
    private func actionRows(actions: (go: Bool, adjust: Bool), showsAdjust: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { decideButtons(actions: actions, showsAdjust: showsAdjust, stacked: false) }
            VStack(spacing: 10) { decideButtons(actions: actions, showsAdjust: showsAdjust, stacked: true) }
        }
        .controlSize(.large)
        if !showAdjust, let message = overrideModel?.errorMessage {
            Text(message).jiFont(.caption).foregroundStyle(theme.color(.danger))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.decide.error")
        }
    }

    /// W-FIX4 PF-01: Decide is its own screen — the card scrolls, Go / Adjust stay pinned above the
    /// floating tab bar (forced gate and first-of-day alike, both schemes, every type size).
    public var body: some View {
        let actions = decideActions(verdict: verdict, syncing: syncing)
        let showsAdjust = actions.adjust && overrideModel != nil && verdictDate != nil
        let pinned = decideActionsPinned(offscreen: offscreen)
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                if let banner { banner }
                card(actions: actions, showsAdjust: showsAdjust, inlineActions: !pinned)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinned {
                VStack(spacing: 8) { actionRows(actions: actions, showsAdjust: showsAdjust) }
                    .padding(.horizontal, 20).padding(.top, 12)
                    .readableColumn()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12 + decideActionBarBottomClearance(sizeClass == .regular ? .regular : .compact))
                    .background { JIPageGround().opacity(0.92) }   // W-GUI T1: the ground, not a flat bar
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today.decide.actions")
            }
        }
        .sheet(isPresented: $showAdjust) { adjustSheet }
        // Advance only when the write actually settled (`.logged` or `.queued`) — never on `.failed`.
        .onChange(of: overrideModel?.settled ?? false) { _, settled in
            if settled { showAdjust = false; advance() }
        }
    }

    /// W-GUI T1 (mockup 01): the tinted hero — date + pill, verdict, session, the one human why,
    /// the readiness ring with its honest reason — then "What drove it" as its own grouped card
    /// with the signal rows and "How the morning call works", and the RMSSD / SDNN footnote once.
    @ViewBuilder
    private func card(actions: (go: Bool, adjust: Bool), showsAdjust: Bool, inlineActions: Bool) -> some View {
        Surface(level: 1, padding: JISpacing.cardPadding, tint: decideHeroTintRole(tone: shown.tone, syncing: syncing).map { theme.color($0) }) {
            VStack(alignment: .leading, spacing: 12) {
                // r4 AX3: side by side while both fit whole; otherwise the pill drops under the date
                // (never squeezed into a one-character-per-line column).
                let dateText = Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .jiFont(.subheadline, weight: .semibold).foregroundStyle(theme.color(.muted))
                ViewThatFits(in: .horizontal) {
                    HStack {
                        dateText.fixedSize()
                        Spacer()
                        SyncedPill(date: syncedAt, now: now).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        dateText.fixedSize(horizontal: false, vertical: true)
                        SyncedPill(date: syncedAt, now: now).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(decideCallHeader(verdictDate: verdictDate, isStale: isStale, today: RecoveryInsightService.localDayKey(now))).jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(syncing ? .muted : verdictColorRole(shown.tone)))
                // AX sizes: the ring drops under the words (side by side it squeezed the verdict to one
                // character per line); below AX it sits beside them as in mockup 01.
                let heroLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: JISpacing.s3))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: JISpacing.s3))
                heroLayout {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(syncing ? "Syncing…" : decideWord(shown))
                            .jiNumeral(.numeralHero, weight: .heavy)
                            .foregroundStyle(theme.color(syncing ? .muted : verdictColorRole(shown.tone)))
                            .lineLimit(1).minimumScaleFactor(0.4)
                            .accessibilityLabel(heroRingAccessibilityLabel(label: "Readiness", value: readiness))
                            .accessibilityIdentifier("today.readinessGauge")
                        if !syncing, !shown.session.isEmpty {
                            Text(shown.session).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("today.verdict.session")
                        }
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    let hubRecovery = decideHubRecovery(gateSignals)
                    DecideReadinessRing(score: decideRingScore(readiness: readiness, recovery: recoveryInsight?.result, hubRecovery: hubRecovery),
                                        nights: calibrationNights, recovery: readiness == nil ? recoveryInsight?.result : nil,
                                        hubRecovery: readiness == nil ? hubRecovery : nil)
                }
                if !syncing, let wasCaption {
                    Text(wasCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("today.decide.was")
                }
                if !syncing {
                    // The one human why (`decideWhyLine`): W-FIX10 R-05 the held "Waiting for the
                    // watch…" reason (even with gate signals), else the hub's reduced prescription on
                    // an amber day, else the verdict's own reason line (a pre-048 verdict).
                    switch decideWhyLine(verdict: verdict, override: override, hasGateSignals: gateSignals != nil,
                                         heldReason: heldReason, week: planWeek) {
                    case .held(let held)?:
                        Label(held, systemImage: "applewatch").jiFont(.footnote, weight: .semibold)
                            .foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("today.decide.held")
                    case .prescription(let prescription)?:
                        Text(prescription).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("today.decide.prescription")
                    case .reason(let reason)?:
                        Text(reason).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .accessibilityIdentifier("today.decide.reason")
                    case nil:
                        EmptyView()
                    }
                }
                if inlineActions { actionRows(actions: actions, showsAdjust: showsAdjust) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !syncing {
            JISectionHeader("What drove it")
            Surface(level: 1, padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if let gateSignals {
                        // B-57 W3: the gate's `recovery` signal is the score row below, not a second SignalRow.
                        DecideSignalsSection(signals: RecoveryScoreCard.visibleSignals(gateSignals), normals: normals)
                            .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s2)
                    }
                    // B-57 W3 S1: the recovery score (on-device, the gate's own inputs) under the signals.
                    // W-FIX7 fixer F7-2: the row says the ring's number (the hub's recovery for the call).
                    RecoveryScoreCard(compact: true, hubRecovery: decideHubRecovery(gateSignals))
                        .padding(.horizontal, JISpacing.s4)
                    JIRowDivider().padding(.leading, JISpacing.s4)
                    let row = decideSessionRowText(sessionForToday: sessionForToday, verdict: shown)
                    // W-FIX1 BUG-17: the whole row opens Day (no write — Go / Adjust record the call).
                    // B-57 W5 C4 (board 1/01): the first lift's next weight at the right, "↑ Bench up" when due.
                    // W-FIX5 W5-3: no weight beside a Rest call; stacked at accessibility sizes.
                    // W-FIX7 F7-1: a matching Apple Health workout today = done (no weight to lift any more).
                    let completion = TodayWorkoutsModel.shared.completion(sessionLabel: row.detail)
                    let lift = completion.isDone ? nil : decideSessionLiftShown(verdict: shown, sessionDetail: row.detail,
                                                      lifts: progression?.lifts(forSession: todaysStrengthSession(week)) ?? [])
                    Button { openDay() } label: {
                        JIChevronRow { sessionRowLabel(row, lift: lift, completion: completion) }
                        .padding(.horizontal, JISpacing.s4)
                    }
                    .task { if !offscreen { await progression?.refreshIfNeeded() } }
                    .buttonStyle(.pressableScale)
                    .disabled(!decideSessionRowOpensDay(syncing: syncing) || submitting)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens your day")
                    .accessibilityIdentifier("today.decide.session")
                    JIRowDivider().padding(.leading, JISpacing.s4)
                    Button { if gateConfigModel != nil { showGateConfig = true } } label: {
                        JIChevronRow(title: "How the morning call works", value: nil, systemImage: "questionmark.circle")
                            .padding(.horizontal, JISpacing.s4)
                    }
                    .buttonStyle(.pressableScale)
                    .disabled(gateConfigModel == nil)
                    .accessibilityHint(gateConfigModel == nil ? "" : "Opens the morning call settings")
                    .accessibilityIdentifier("today.decide.gateConfig")
                }
                .padding(.vertical, 6)
            }
            .navigationDestination(isPresented: $showGateConfig) {
                if let gateConfigModel { GateConfigView(model: gateConfigModel) }
            }
            Text(decideHrvFootnote).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JISpacing.s4)
                .accessibilityIdentifier("today.decide.hrvFootnote")
        }
    }

    @ViewBuilder
    private var adjustSheet: some View {
            if let overrideModel, let verdictDate {
                NavigationStack {
                    ScrollView {
                        VerdictAdjustForm(verdict: verdict, sessionForToday: sessionForToday, model: overrideModel) { choice, reason in
                            Task { _ = await decideSubmit(model: overrideModel, date: verdictDate, choice: choice, reason: reason,
                                                          parts: verdict, sessionForToday: sessionForToday) }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .jiPageGround()
                    .background(theme.color(.bg))
                    .navigationTitle("Adjust")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdjust = false }
                                .accessibilityIdentifier("today.decide.adjust.cancel")
                        }
                    }
                }
                .jiTheme(theme)
                .presentationDetents([.medium, .large])
            }
    }

    private func go() {
        // No hub write seam (older provider / no database): nothing to record — just move on.
        guard let overrideModel, let verdictDate else { advance(); return }
        // W-FIX11 H1-01: a call already shown (Adjust → Rest) is kept — Go never replaces it with
        // the hub verdict.
        guard decideGoChoice(override: override) != nil else { advance(); return }
        Task {
            _ = await decideGo(model: overrideModel, date: verdictDate, override: override,
                               parts: verdict, sessionForToday: sessionForToday)
        }   // onChange(settled) advances
    }

    private func openDay() {
        guard decideSessionRowOpensDay(syncing: syncing) else { return }
        onAdvance()
    }

    private func advance() {
        if !offscreen { JIHaptic.fire(.saveSuccess) }
        onAdvance()
    }
}

/// W-B57b (B-62) Adjust: "my call" — the choice picker (full / modified / rest) plus the existing
/// reason list (`GateRespondCopy.overrideReasons`). Save writes the override; the sheet closes and
/// Decide advances only when the write settles.
public struct VerdictAdjustForm: View {
    let verdict: VerdictParts
    let sessionForToday: String?
    let model: VerdictOverrideViewModel?
    let onSave: (VerdictOverrideChoice, String) -> Void
    @State private var choice: VerdictOverrideChoice?
    @State private var reasonChoice: String?
    @State private var otherText = ""
    @Environment(\.jiTheme) private var theme

    public init(verdict: VerdictParts, sessionForToday: String?, model: VerdictOverrideViewModel?,
                initialChoice: VerdictOverrideChoice? = nil, initialReason: String? = nil,
                onSave: @escaping (VerdictOverrideChoice, String) -> Void) {
        self.verdict = verdict; self.sessionForToday = sessionForToday; self.model = model; self.onSave = onSave
        _choice = State(initialValue: initialChoice)
        _reasonChoice = State(initialValue: initialReason)
    }

    private var reason: String {
        guard let reasonChoice else { return "" }
        return reasonChoice == GateRespondCopy.otherReason ? otherText.trimmingCharacters(in: .whitespacesAndNewlines) : reasonChoice
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            formLabel("Today I'll do")
            VStack(spacing: 8) {
                ForEach(adjustChoices(parts: verdict, sessionForToday: sessionForToday)) { option in
                    choiceRow(option)
                }
            }
            formLabel("Why")
            VStack(spacing: 6) {
                ForEach(GateRespondCopy.overrideReasons, id: \.self) { r in reasonRow(r) }
            }
            if reasonChoice == GateRespondCopy.otherReason {
                TextField("Your reason", text: $otherText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("today.decide.adjust.otherText")
            }
            if let message = model?.errorMessage {
                Text(message).jiFont(.caption).foregroundStyle(theme.color(.danger))
                    .accessibilityIdentifier("today.decide.adjust.error")
            }
            Button {
                if let choice { onSave(choice, reason) }
            } label: {
                Text("Save my call").frame(maxWidth: .infinity)
            }
            .buttonStyle(.jiPrimary)   // W-GUI T2: the sheet's one primary
            .disabled(choice == nil || model?.phase == .submitting)
            .accessibilityIdentifier("today.decide.adjust.save")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formLabel(_ text: String) -> some View {
        Text(text).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
            .accessibilityAddTraits(.isHeader)
    }

    private func choiceRow(_ option: AdjustChoice) -> some View {
        let selected = choice == option.choice
        return Button { choice = option.choice } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    Text(option.session).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? theme.color(.info) : theme.color(.muted))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(.control), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
            .overlay(RoundedRectangle(cornerRadius: theme.radius(.control)).stroke(selected ? theme.color(.info) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableScale)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("today.decide.adjust.choice.\(option.choice.rawValue)")
    }

    /// W-FIX1 BUG-18: padding, width and background sit INSIDE the Button's label (with a
    /// rectangular content shape), so a tap anywhere on the full-width row selects the reason —
    /// not only on its text, as the choice rows above already do.
    private func reasonRow(_ r: String) -> some View {
        let selected = reasonChoice == r
        return Button { reasonChoice = r } label: {
            Text(r)
                .jiFont(.footnote, weight: .semibold)
                .foregroundStyle(selected ? theme.color(.info) : theme.color(.text))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(theme.color(.control), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                .overlay(RoundedRectangle(cornerRadius: theme.radius(.control)).stroke(selected ? theme.color(.info) : .clear))
                .contentShape(Rectangle())
        }
            .buttonStyle(.pressableScale)
            .accessibilityLabel(r)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("today.decide.adjust.reason.\(r)")
    }
}


// MARK: - W-GUI T1: readiness ring

/// The readiness ring beside the verdict (mockup 01): the score in a ring when the hub has one,
/// else "—" with the honest caption (plan §B: the score lands in W3). The number is never a
/// verdict colour (rule 6): it wears the text colour; the ring track is the nested fill.
struct DecideReadinessRing: View {
    let score: Double?, nights: Int?
    var recovery: RecoveryScoreResult? = nil
    var hubRecovery: Double? = nil
    @Environment(\.jiTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 64

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let score {
                    ScoreRing(value: score, max: 100, tint: theme.color(.text), size: side)
                    Text(jiNumber(score, 0)).jiNumeral(.numeralSmall, tint: .text)
                } else {
                    Circle().stroke(theme.color(.nested), lineWidth: side * 0.14).frame(width: side, height: side)
                    Text("—").jiNumeral(.numeralSmall, tint: .muted)
                }
            }
            Text(decideReadinessCaption(score: score, nights: nights, recovery: recovery, hubRecovery: hubRecovery))
                .jiFont(.micro).foregroundStyle(theme.color(.muted))
                .multilineTextAlignment(.center)
                .frame(width: side * 1.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(decideReadinessCaption(score: score, nights: nights, recovery: recovery, hubRecovery: hubRecovery) + (score.map { ", \(jiNumber($0, 0))" } ?? ""))
        .accessibilityIdentifier("today.decide.readinessRing")
    }
}

/// W-FIX7 F7-1: the session's status from Apple Health — "Done · Traditional strength · 52 min ·
/// Bevel" (a check, status green — rule 6) or "Other activity · Walk · 30 min · Workout" (muted,
/// the session stays open). Nothing at all when Health has no workout today.
public struct SessionCompletionLine: View {
    let text: String?
    let isDone: Bool
    @Environment(\.jiTheme) private var theme

    public init(completion: SessionCompletion) { self.text = completion.statusText; self.isDone = completion.isDone }

    /// W-FIX9: NEXT's line from the session's parts — ticked once any part is done, and naming it.
    public init(progress: SessionProgress) { self.text = progress.statusText; self.isDone = progress.anyDone }

    /// W-FIX9 fixer (FIX9V-4): NEXT's line with the hub rows under it (`dayNextDoneLine`).
    public init(progress: SessionProgress, hubWorkouts: [DayActivity]) {
        self.text = dayNextDoneLine(progress, hubWorkouts: hubWorkouts); self.isDone = progress.anyDone
    }

    public var body: some View {
        if let text {
            Label {
                Text(text).jiFont(.caption, weight: .semibold).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "figure.mixed.cardio")
            }
            .foregroundStyle(theme.color(isDone ? .go : .muted))
            .accessibilityIdentifier(isDone ? "session.done" : "session.otherActivity")
        }
    }
}

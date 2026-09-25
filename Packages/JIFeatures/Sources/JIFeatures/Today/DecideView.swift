import SwiftUI
import JICore
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

/// Decide's big word: the user-facing word (`verdictUserWord` — "GO" → "Full", "MODIFIED (HRV low)"
/// → "Modified"), without RN's parenthetical, which never fits; the reason is carried by the Why
/// rows (or the reason line when there are none).
public nonisolated func decideWord(_ parts: VerdictParts) -> String { verdictUserWord(parts) }

/// B-57 W1 Decide "Session" row. The hub sends no session time or exercise list to Today, so W1
/// shows the session name only (time, exercises and first working weight: W5 progression).
/// W-FIX1 BUG-03: the line under Decide's session on an amber (auto-regulated) day — the hub's
/// reduced prescription, so "Modified" says what changed. nil on every other verdict and once the
/// user made another call (full / modified / rest).
public nonisolated func decidePrescriptionLine(verdict: VerdictParts, override: VerdictOverride?) -> String? {
    if let override, override.choice != .accept { return nil }
    return autoRegulatedPrescription(verdict)
}

/// W-FIX1 BUG-17: Decide's "Today's session" row links to Day (spec §2 L2) — live whenever the
/// verdict is in (while syncing there is no Day to show yet).
public nonisolated func decideSessionRowOpensDay(syncing: Bool) -> Bool { !syncing }

public nonisolated func decideSessionRowText(sessionForToday: String?, verdict: VerdictParts) -> (title: String, detail: String) {
    let name = [sessionForToday, verdict.session].compactMap { $0 }.first { !$0.isEmpty }
    return ("Today's session", name ?? "— \(JIMissingReason.noData.rawValue)")
}

/// W-FIX3 BUG-30 (board 01): Go's label is black on the green verdict button.
public nonisolated let decideGoForeground = Color.black

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
    let now: Date
    let onAdvance: () -> Void
    @State private var showAdjust = false
    @Environment(\.jiTheme) private var theme
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(verdict: VerdictParts, readiness: Double?, syncing: Bool, gateSignals: [GateSignal]?,
                verdictDate: String?, sessionForToday: String?, override: VerdictOverride?,
                overrideModel: VerdictOverrideViewModel?, syncedAt: Date?, normals: [String: ClosedRange<Double>] = [:],
                now: Date = Date(), onAdvance: @escaping () -> Void) {
        self.verdict = verdict; self.readiness = readiness; self.syncing = syncing
        self.gateSignals = gateSignals; self.verdictDate = verdictDate; self.sessionForToday = sessionForToday
        self.override = override; self.overrideModel = overrideModel
        self.syncedAt = syncedAt; self.normals = normals; self.now = now; self.onAdvance = onAdvance
    }

    /// Pre-W-FIX3 entry (App `RootTabView.gateScreen`, not this lane's file): it hands the FETCH
    /// time and keeps showing it until that call site passes `syncedAt: model.syncedAt`
    /// (W-FIX3 C-f hand-off).
    @available(*, deprecated, message: "W-FIX3 C-f: pass syncedAt: TodayViewModel.syncedAt")
    public init(verdict: VerdictParts, readiness: Double?, syncing: Bool, gateSignals: [GateSignal]?,
                verdictDate: String?, sessionForToday: String?, override: VerdictOverride?,
                overrideModel: VerdictOverrideViewModel?, fetchedAt: Date?, now: Date = Date(),
                onAdvance: @escaping () -> Void) {
        self.init(verdict: verdict, readiness: readiness, syncing: syncing, gateSignals: gateSignals, verdictDate: verdictDate,
                  sessionForToday: sessionForToday, override: override, overrideModel: overrideModel, syncedAt: fetchedAt,
                  now: now, onAdvance: onAdvance)
    }

    private var shown: VerdictParts { effectiveVerdictParts(parts: verdict, override: override) }
    private var wasCaption: String? { override == nil ? nil : effectiveVerdict(parts: verdict, override: override).wasCaption }
    private var submitting: Bool { overrideModel?.phase == .submitting }

    @ViewBuilder
    private func decideButtons(actions: (go: Bool, adjust: Bool), showsAdjust: Bool, stacked: Bool) -> some View {
        // W-FIX3 BUG-30 (board 01): black "Go" on the green button, never white.
        Button { go() } label: { Text("Go").foregroundStyle(decideGoForeground).lineLimit(1).fixedSize().frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(theme.color(.go))
            .disabled(!actions.go || submitting)
            .accessibilityIdentifier("today.decide.go")
        if showsAdjust {
            Button { showAdjust = true } label: {
                Text("Adjust").lineLimit(1).fixedSize().frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .disabled(submitting)
            .accessibilityIdentifier("today.decide.adjust")
        }
    }

    public var body: some View {
        let actions = decideActions(verdict: verdict, syncing: syncing)
        let showsAdjust = actions.adjust && overrideModel != nil && verdictDate != nil
        Surface(level: 1, padding: 24) {
            VStack(alignment: .leading, spacing: 14) {
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
                Text("YOUR CALL FOR TODAY").jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(syncing ? .muted : verdictColorRole(shown.tone)))
                Text(syncing ? "Syncing…" : decideWord(shown))
                    .jiNumeral(.numeralDisplay, weight: .heavy)
                    .foregroundStyle(theme.color(syncing ? .muted : verdictColorRole(shown.tone)))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .accessibilityLabel(heroRingAccessibilityLabel(label: "Readiness", value: readiness))
                    .accessibilityIdentifier("today.readinessGauge")
                if !syncing, !shown.session.isEmpty {
                    Text(shown.session).jiFont(.cardTitleLarge, weight: .bold).foregroundStyle(theme.color(.text))
                        .accessibilityIdentifier("today.verdict.session")
                }
                if !syncing, let wasCaption {
                    Text(wasCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("today.decide.was")
                }
                if !syncing {
                    if let prescription = decidePrescriptionLine(verdict: verdict, override: override) {
                        Text(prescription).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("today.decide.prescription")
                    }
                    if let gateSignals {
                        DecideSignalsSection(signals: gateSignals, normals: normals)
                    } else if let reason = verdictReasonLine(verdict) {
                        Text(reason).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .accessibilityIdentifier("today.decide.reason")
                    }
                    let row = decideSessionRowText(sessionForToday: sessionForToday, verdict: shown)
                    // W-FIX1 BUG-17: the whole row opens Day (no write — Go / Adjust record the call).
                    Button { openDay() } label: {
                        Surface(level: 2) {
                            HStack(spacing: 12) {
                                Image(systemName: "dumbbell").foregroundStyle(theme.color(.info)).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                                    Text(row.detail).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(theme.color(.muted)).accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableScale)
                    .disabled(!decideSessionRowOpensDay(syncing: syncing) || submitting)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens your day")
                    .accessibilityIdentifier("today.decide.session")
                }
                // r4 AX3: Go / Adjust side by side while both labels fit whole; otherwise stacked
                // full-width (no "Ad-just" hyphenation).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { decideButtons(actions: actions, showsAdjust: showsAdjust, stacked: false) }
                    VStack(spacing: 10) { decideButtons(actions: actions, showsAdjust: showsAdjust, stacked: true) }
                }
                .controlSize(.large)
                if !showAdjust, let message = overrideModel?.errorMessage {
                    Text(message).jiFont(.caption).foregroundStyle(theme.color(.danger))
                        .accessibilityIdentifier("today.decide.error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showAdjust) {
            if let overrideModel, let verdictDate {
                NavigationStack {
                    ScrollView {
                        VerdictAdjustForm(verdict: verdict, sessionForToday: sessionForToday, model: overrideModel) { choice, reason in
                            Task { _ = await decideSubmit(model: overrideModel, date: verdictDate, choice: choice, reason: reason,
                                                          parts: verdict, sessionForToday: sessionForToday) }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
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
        // Advance only when the write actually settled (`.logged` or `.queued`) — never on `.failed`.
        .onChange(of: overrideModel?.settled ?? false) { _, settled in
            if settled { showAdjust = false; advance() }
        }
    }

    private func go() {
        // No hub write seam (older provider / no database): nothing to record — just move on.
        guard let overrideModel, let verdictDate else { advance(); return }
        Task {
            _ = await decideSubmit(model: overrideModel, date: verdictDate, choice: .accept, reason: "",
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
            .buttonStyle(.borderedProminent).tint(theme.color(.info)).controlSize(.large)
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

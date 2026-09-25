import SwiftUI
import JICore
import JIDesign

/// The gate's own reasoning (triggered rules + suggestions) plus the 3-day decision trail — the
/// oracle's `mobile/app/gate-rationale.tsx`, reached by tapping the verdict hero on Today
/// (`VerdictHero.tsx:404` → `router.push("/gate-rationale")`).
///
/// Two branches, exactly as the oracle: the live rationale, and the deep-link per-date branch which
/// deliberately shows less (the persisted `morning_verdict` row has no rules/suggestions/trail).
/// B-57 W1 Recovery score card copy (board 03). The score is W3; the card shows "—" + Calibrating.
/// No night count: the threshold is W3's to set, so none is invented here.
public nonisolated let gateRationaleRecoveryScoreCopy = "One score from overnight HRV, resting HR and sleep (length, deep, REM), each against your normal. It shows a number once all three have enough nights."

// MARK: - W-FIX3 BUG-29 / BUG-33 (board 03)

/// Board 03 has no page title — "< Today" then the card. A title here was "Readiness rati…" at AX3.
public nonisolated let gateRationaleNavigationTitle = ""
/// The card's own heading above the verdict word (board: "WHY TODAY IS Full").
public nonisolated let gateRationaleHeaderLabel = "WHY TODAY IS"

/// The live rationale's sections in board order. The "Recovery score — Calibrating" card is gone:
/// board 03 shows what counted, one row per signal, not a score that does not exist yet.
public nonisolated enum GateRationaleSection: Equatable, Sendable { case whatCounted, weeklyNutrition, lastDays }
public nonisolated let gateRationaleLiveSections: [GateRationaleSection] = [.whatCounted, .weeklyNutrition, .lastDays]

/// "HRV" stays "HRV", "Resting HR" becomes "resting HR" — mid-sentence without breaking acronyms.
nonisolated func gateRationaleMidSentence(_ label: String) -> String {
    guard let first = label.first, label.count > 1, label[label.index(after: label.startIndex)].isLowercase else { return label }
    return first.lowercased() + label.dropFirst()
}

/// Board 03's plain sentence under the verdict word, built only from the hub's gate signals:
/// sleep against its goal, then every signal that flagged or has no reading. `nil` without signals.
public nonisolated func gateRationaleWhySentence(signals: [GateSignal]?) -> String? {
    let gating = (signals ?? []).filter { $0.status != .context }
    guard !gating.isEmpty else { return nil }
    var parts: [String] = []
    var otherPassed = false
    for sig in gating {
        let label = gateRationaleMidSentence(decideSignalLabel(sig))
        let goal = decideCompactNumber(sig.threshold)
        if sig.key == "sleep_h" {
            guard sig.value != nil else { parts.append("sleep has no reading, so it is left out"); continue }
            parts.append(sig.status == .pass ? "sleep cleared the \(goal) h goal" : "sleep was under the \(goal) h goal")
            continue
        }
        guard sig.value != nil, sig.status != .missing else { parts.append("\(label) has no reading, so it is left out"); continue }
        let low = sig.direction == .min
        switch sig.status {
        case .pass: otherPassed = true
        case .amber: parts.append("\(label) is \(low ? "low" : "high")")
        case .red: parts.append("\(label) is very \(low ? "low" : "high")")
        case .missing, .context: break
        }
    }
    if parts.isEmpty { return "Every signal is in range." }
    let flagged = parts.count > (gating.contains { $0.key == "sleep_h" } ? 1 : 0)
    if otherPassed, !flagged { parts.append(parts.isEmpty ? "every signal is in range" : "every other signal is in range") }
    let joined = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
    return joined.prefix(1).uppercased() + joined.dropFirst() + "."
}

/// One "What counted" row (board 03): value + status word + what it did to the call.
public nonisolated struct GateCountedRow: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?, unit: String, decimals: Int
    public let status: JISignalStatus, sentence: String
}

/// Board 03 "What counted": one row per gate signal in the hub's order, then Load (shown for
/// context — it is not part of the morning call). A missing value is "No data" and left out.
public nonisolated func gateRationaleCountedRows(signals: [GateSignal]?, normals: [String: ClosedRange<Double>],
                                                 load: Double?) -> [GateCountedRow] {
    var rows: [GateCountedRow] = (signals ?? []).map { sig in
        let m = decideSignalRowModel(sig, normal: normals[sig.key])
        let sentence: String
        if sig.status == .context {
            sentence = [gateSignalNoteText(sig).map { $0.prefix(1).uppercased() + $0.dropFirst() + "." }, "Shown, not counted."]
                .compactMap { $0 }.joined(separator: " ")
        } else if sig.value == nil || sig.status == .missing {
            sentence = "No overnight value yet. Left out, not counted as bad."
        } else if sig.key == "sleep_h" {
            let goal = decideCompactNumber(sig.threshold)
            sentence = sig.status == .pass ? "Above your \(goal) h goal, so intervals and heavy days stay open." : "Under your \(goal) h goal."
        } else if let normal = m.normal, let v = sig.value {
            let band = "\(jiNumber(normal.lowerBound, 0))–\(jiNumber(normal.upperBound, 0))"
            sentence = v < normal.lowerBound ? "Under your \(band) normal." : v > normal.upperBound ? "Above your \(band) normal." : "Inside your \(band) normal."
        } else {
            let side = sig.status == .pass ? "Clears" : (sig.direction == .min ? "Under" : "Over")
            sentence = "\(side) the morning call's line; your normal is still calibrating."
        }
        return GateCountedRow(id: sig.key, label: m.label, value: sig.value, unit: sig.unit, decimals: m.decimals,
                              status: m.status, sentence: sentence)
    }
    rows.append(GateCountedRow(id: "load", label: "Load", value: load, unit: "", decimals: 2,
                               status: load == nil ? .missing(.calibrating) : .contextOnly,
                               sentence: load == nil ? "No current load reading. Left out." : "Shown for context; load is not part of the morning call."))
    return rows
}

public struct GateRationaleView: View {
    @Bindable var model: GateRationaleViewModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen
    /// W-B57b: the weekly gate answer card's model (see `EnvironmentValues.gateRespondModel`).
    @Environment(\.gateRespondModel) private var respondModel

    public init(model: GateRationaleViewModel) { self.model = model }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                switch model.phase {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .noVerdictForDate(let copy):
                    // The ONE benign failure — nothing to retry, so no Retry button (oracle).
                    Surface {
                        Text(copy).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .accessibilityIdentifier("gateRationale.noVerdict")
                    }
                case .error(let message):
                    errorCard(message)
                case .loaded:
                    verdictCard
                    if model.isByDate {
                        byDateReasonCard
                    } else {
                        // Board 03 GateRationale (`gateRationaleLiveSections`): What counted →
                        // Weekly nutrition → Last 3 days. W-FIX3 BUG-29: no "— Calibrating" score card.
                        whatCountedCard
                        weeklyNutritionSection
                        lastDaysSection
                    }
                    // W-B57b (§9): the WEEKLY gate response left Today — it lives here, at the
                    // bottom of the rationale, built by Today's `makeGateRespondModel` path and
                    // handed down through `\.gateRespondModel` (nil = no card, as before).
                    if let respondModel {
                        GateRespondCard(model: respondModel, showsFeelRow: false)
                            .accessibilityIdentifier("gateRationale.weeklyRespond")
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableColumn()
        }
        .background(theme.color(.bg))
        // W-FIX3 BUG-29/33: no page title ("Readiness rati…" at AX3) — the card says WHY TODAY IS.
        .navigationTitle(gateRationaleNavigationTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { if !offscreen { await model.load() } }
    }

    // MARK: - Cards

    private func errorCard(_ message: String) -> some View {
        Surface {
            VStack(spacing: 10) {
                Text(message).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                Button("Retry") { Task { await model.refresh() } }
                    .buttonStyle(.pressableScale)
                    .accessibilityLabel("Retry loading the readiness rationale")
                    .accessibilityIdentifier("gateRationale.retry")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var verdictCard: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 4) {
                // W-FIX3 BUG-29 (board 03): "Computed 07:41" first, then WHY TODAY IS + the word + a sentence.
                if let time = model.computedAtTime() {
                    Text("Computed \(time)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("gateRationale.computed")
                }
                sectionLabel(gateRationaleHeaderLabel)
                    .accessibilityAddTraits(.isHeader)
                // r5: Decide's user-facing word ("Full" / "Modified" / "Rest"), never the hub's GO.
                Text(model.verdictWord)
                    .jiNumeral(.numeralLarge, weight: .heavy)
                    .foregroundStyle(theme.color(verdictColorRole(model.verdict.tone)))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .accessibilityIdentifier("gateRationale.verdict.word")
                if let sentence = gateRationaleWhySentence(signals: model.morning?.gateSignals) {
                    Text(sentence).jiFont(.body).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateRationale.verdict.sentence")
                }
                if !model.verdict.session.isEmpty {
                    Text(model.verdict.session).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateRationale.verdict.session")
                }
                // W-FIX1 BUG-03: an amber (auto-regulated) day says what it trims and why.
                if let prescription = model.verdictPrescription {
                    Text(prescription).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateRationale.verdict.prescription")
                }
                if let why = model.verdictWhy {
                    Text("Why: \(why)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("gateRationale.verdict.why")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var byDateReasonCard: some View {
        if let reason = model.verdictForDate?.reason, !reason.isEmpty {
            card("Why") {
                Text(reason).jiFont(.footnote).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("gateRationale.byDate.reason")
            }
        }
    }

    /// W-FIX3 BUG-29 (board 03 "What counted"): Sleep / Overnight HRV / Resting HR / Load, each with its
    /// value, status word and what it did to the call — not a copy of Decide's rows.
    @ViewBuilder private var whatCountedCard: some View {
        let rows = gateRationaleCountedRows(signals: model.morning?.gateSignals,
                                            normals: decideSignalNormals(recovery: model.recovery),
                                            load: KpiMetrics.currentAcwr(model.recovery, now: Date()))
        VStack(alignment: .leading, spacing: 10) {
            boardHeader("What counted", trailing: nil)
            Surface(level: 2, padding: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(rows) { countedRow($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("gateRationale.whatCounted")
        }
    }

    private func countedRow(_ row: GateCountedRow) -> some View {
        let valueLine = HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(jiValueText(row.value, decimals: row.decimals)).jiFont(.body, weight: .bold)
                .foregroundStyle(theme.color(row.value == nil ? .muted : row.status.role))
            if row.value != nil, !row.unit.isEmpty { Text(row.unit).jiFont(.caption).foregroundStyle(theme.color(.muted)) }
            Text(row.status.word).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(row.status.role))
        }
        let label = Text(row.label).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.status.symbolName)
                .jiFont(.footnote, weight: .bold).foregroundStyle(theme.color(row.status.role))
                .frame(width: 30, height: 30).background(theme.color(.surface3), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { label; Spacer(minLength: 8); valueLine }
                    VStack(alignment: .leading, spacing: 2) { label; valueLine }
                }
                Text(row.sentence).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label), \(row.value.map { "\(jiNumber($0, row.decimals)) \(row.unit)" } ?? "no value"), \(row.status.word). \(row.sentence)")
        .accessibilityIdentifier("gateRationale.counted.\(row.id)")
    }

    /// Board "Weekly nutrition · 7-day": Energy balance + Protein tiles from the weekly gate's own
    /// averages ("—" + No data when absent), then the gate's recommendation / rules / suggestions as
    /// the caption, then the balance explainer. Plan band, deficit class and the protein goal are
    /// W2 (goals/band), so those spots are left out.
    private var weeklyNutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            boardHeader("Weekly nutrition", trailing: "7-day")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { energyTile; proteinTile }
                VStack(alignment: .leading, spacing: 12) { energyTile; proteinTile }
            }
            let notes = model.weeklyNotes()
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, line in
                        Text(line).jiFont(.footnote).foregroundStyle(theme.color(.text))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("gateRationale.weeklyNotes")
            }
            HowWeCalculateLink("How JI calculates balance and the plan band", title: JIExplainers.energyBalanceTitle,
                               steps: JIExplainers.energyBalanceSteps, note: JIExplainers.energyBalanceNote)
        }
    }

    private var energyTile: some View {
        weeklyTile(title: "Energy balance", systemImage: "flame", tint: metricTintRole("kcal"), value: model.energyBalance7d,
                   signed: true, unit: "kcal/day", id: "gateRationale.energyBalance")
    }

    private var proteinTile: some View {
        weeklyTile(title: "Protein", systemImage: "fork.knife", tint: metricTintRole("protein"), value: model.protein7d,
                   signed: false, unit: "g a day", id: "gateRationale.protein")
    }

    private func weeklyTile(title: String, systemImage: String, tint: JIColorRole, value: Double?, signed: Bool,
                            unit: String, id: String) -> some View {
        Surface(level: 2, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage).jiFont(.subheadline, weight: .semibold)
                    .foregroundStyle(theme.color(tint))
                if let value {
                    let text = signed && value > 0 ? "+\(jiNumber(value, 0))" : jiNumber(value, 0)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(text).jiNumeral(.numeralMedium, weight: .heavy).foregroundStyle(theme.color(tint))
                            Text(unit).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(text).jiNumeral(.numeralMedium, weight: .heavy).foregroundStyle(theme.color(tint))
                            Text(unit).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        }
                    }
                } else {
                    Text("—").jiNumeral(.numeralMedium, tint: .muted)
                    Text(JIMissingReason.noData.rawValue).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\(jiNumber($0, 0)) \(unit), 7-day average" } ?? "No data")
        .accessibilityIdentifier(id)
    }

    /// Board "Last 3 days": date · session · verdict word, newest first. A day with no persisted
    /// verdict reads "—" + No data (never a guessed session).
    private var lastDaysSection: some View {
        let rows = model.lastDays()
        return VStack(alignment: .leading, spacing: 10) {
            boardHeader("Last 3 days", trailing: nil)
            Surface(level: 2, padding: 0) {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text("— \(JIMissingReason.noData.rawValue)").jiFont(.footnote).foregroundStyle(theme.color(.muted))
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().overlay(theme.color(.hairlineNested)) }
                        lastDayRow(row)
                    }
                }
            }
            .accessibilityIdentifier("gateRationale.lastDays")
        }
    }

    private func lastDayRow(_ row: GateDayRow) -> some View {
        let dayText = Text(row.dayLabel).jiFont(.body).foregroundStyle(theme.color(.muted))
        let sessionLine = Text(row.session ?? (row.verdictWord == nil ? "—" : "")).jiFont(.body)
            .foregroundStyle(theme.color(row.session == nil ? .muted : .text))
            .fixedSize(horizontal: false, vertical: true)
        // W-FIX1 BUG-03: an amber day's row carries its trimmed prescription under the session.
        let session = VStack(alignment: .leading, spacing: 2) {
            sessionLine
            if let prescription = row.prescription {
                Text(prescription).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        let verdict = Text(row.verdictWord ?? JIMissingReason.noData.rawValue)
            .jiFont(.body, weight: .semibold)
            .foregroundStyle(theme.color(row.verdictWord == nil ? .muted : verdictColorRole(row.tone)))
            .fixedSize(horizontal: false, vertical: true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                dayText.fixedSize()
                session.frame(maxWidth: .infinity, alignment: .leading)
                verdict.multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack { dayText; Spacer(minLength: 8); verdict }
                session
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.dayLabel): \(row.session ?? "no session")\(row.prescription.map { ", \($0)" } ?? ""), \(row.verdictWord ?? "no data")")
    }

    private func boardHeader(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).jiFont(.subheadline).foregroundStyle(theme.color(.muted)) }
        }
    }

    // MARK: - Primitives

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        Surface(level: 2, padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(title)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// §2: the uppercase footnote header, from JIDesign (unpadded inside a card).
    private func sectionLabel(_ text: String) -> some View {
        JISectionHeader(text).padding(.leading, -16)
    }

    /// "2026-09-11" -> "Thu". Parsed as a plain calendar date (no timezone shift off the hub's day).
    nonisolated static func weekdayLabel(_ date: String, locale: Locale = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return date }
        return d.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated))
    }
}

// MARK: - Entry point

extension EnvironmentValues {
    /// Set by the app's Today wiring; `nil` leaves the verdict hero inert (an optional model,
    /// routed through the environment so the entry site costs exactly one line).
    @Entry public var gateRationaleModel: GateRationaleViewModel?
    /// W-B57b (§9): the weekly gate's answer model, set by `TodayView` (which builds it through
    /// the App's `makeGateRespondModel`) so the rationale screen can show the respond card.
    @Entry public var gateRespondModel: GateRespondViewModel?
    /// W-B57b (B-62): Decide's verdict-override write model, built once by the App next to
    /// `gateRationaleModel`; nil = Go just advances and Adjust is hidden.
    @Entry public var verdictOverrideModel: VerdictOverrideViewModel?
}

/// The rationale screen as every Today entry pushes it: the respond model is re-injected
/// explicitly, because a `navigationDestination` is not guaranteed to inherit the environment of
/// the view that declared it.
@MainActor
func gateRationaleScreen(model: GateRationaleViewModel, respondModel: GateRespondViewModel?) -> some View {
    GateRationaleView(model: model).environment(\.gateRespondModel, respondModel)
}

/// Makes the whole verdict hero the tap target into the rationale — the oracle's `VerdictCard`
/// `onPress` covers the entire card, with `accessibilityLabel="Readiness verdict details"`.
struct GateRationaleDestination: ViewModifier {
    @Environment(\.gateRationaleModel) private var model
    @Environment(\.gateRespondModel) private var respondModel
    @State private var showRationale = false

    func body(content: Content) -> some View {
        if let model {
            Button { showRationale = true } label: { content }
                .buttonStyle(.pressableScale)
                .accessibilityLabel("Readiness verdict details")
                .accessibilityIdentifier("today.verdict.rationale")
                // Attached locally so this never needs the enclosing NavigationStack's own
                // `navigationDestination(for:)`.
                .navigationDestination(isPresented: $showRationale) { gateRationaleScreen(model: model, respondModel: respondModel) }
        } else {
            content
        }
    }
}

extension View {
    /// One-line entry site for `VerdictHeroView` (oracle `VerdictHero.tsx:404`).
    func gateRationaleDestination() -> some View { modifier(GateRationaleDestination()) }
}

import SwiftUI
import JICore
import JIDesign

public struct TodayView: View {
    @Bindable private var model: TodayViewModel
    private let onOpenConnection: () -> Void
    private let onSelectKpi: (String) -> Void
    /// W-FIX2 fixer BUG-13: the shell's router push for Trends (a path route, so a KPI opened from
    /// Trends returns to Trends). Nil (previews, package tests) keeps the local `NavigationLink`.
    private let onOpenTrends: (() -> Void)?
    /// W5b-L4 (P-gate-respond) close-out wiring: builds the gate answer card's model for the loaded
    /// gate's recommendation (the App supplies outbox + decision log); `nil` = no card, as before.
    private let makeGateRespondModel: (GateRecommendation) -> GateRespondViewModel?
    @State private var gateRespondModel: GateRespondViewModel?
    /// B-57 §6/§9: the Day summary line re-opens this morning's Coach overlay, read-only.
    @State private var showMorningReview = false
    /// W-FIX3 BUG-28: board 02's "Week review" footer link opens the gate rationale (weekly gate).
    @State private var showWeekReview = false
    /// W-FIX3 C-g: the Coach card's measured height (it grows with type size and its sentence).
    @State private var coachCardHeight: CGFloat = 0
    @Environment(\.gateRationaleModel) private var rationaleModel
    /// W-B57b (B-62): Decide's Go / Adjust write, built by the App (nil = Go just advances).
    @Environment(\.verdictOverrideModel) private var verdictOverrideModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch and no model rebuild while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen

    public init(model: TodayViewModel, onOpenConnection: @escaping () -> Void, onSelectKpi: @escaping (String) -> Void = { _ in },
                onOpenTrends: (() -> Void)? = nil,
                makeGateRespondModel: @escaping (GateRecommendation) -> GateRespondViewModel? = { _ in nil }) {
        self.model = model; self.onOpenConnection = onOpenConnection; self.onSelectKpi = onSelectKpi
        self.onOpenTrends = onOpenTrends
        self.makeGateRespondModel = makeGateRespondModel
    }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 16) {
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                    .accessibilityLabel("No data yet — run a sync on the hub.")
                case .loaded:
                    // B-57 §2: Decide → Coach → Day, advanced only by what the user does and kept
                    // per verdict date (`TodayViewModel.morningState`).
                    switch model.morningState {
                    case .decide:
                        DecideView(verdict: model.verdict, readiness: model.readiness,
                                   syncing: model.morning?.verdict == nil,
                                   gateSignals: model.morning?.gateSignals,
                                   verdictDate: model.verdictDate,
                                   sessionForToday: model.morning?.sessionForToday,
                                   override: currentOverride,
                                   overrideModel: verdictOverrideModel,
                                   syncedAt: model.syncedAt,
                                   normals: decideSignalNormals(recovery: model.recovery)) { model.morningEvent(.gateResponded) }
                    case .coach, .day:
                        // §9: Coach is the Day view plus a bottom overlay card (below), not a step.
                        dayContent
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .background(theme.color(.bg))
        .refreshable { JIHaptic.fire(.selection); await model.refresh() }   // W8-L1 (P-haptics) — oracle SyncButton.tsx:136 hapticSelection() the instant the sync is kicked off (Swift sync control = pull-to-refresh)
        // §5: the hand-drawn large title becomes the system one; the date line is the subtitle.
        // W-FIX3 BUG-30: Decide carries its own date line — no second "Today / Friday" title above it.
        .navigationTitle(todayNavigationTitle(state: shownMorningState, pageName: loadTodayPageName(prefs: model.tileOrderStore)))
        .navigationSubtitle(todayNavigationSubtitleShown(state: shownMorningState) ? Date().formatted(.dateTime.weekday(.wide).day().month(.wide)) : "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(todayNavigationSubtitleShown(state: shownMorningState) ? .automatic : .inline)
        #endif
        // CODE-1: gate on `hasLiveResult`, not `phase == .idle` — a cancelled fetch over a warm cache
        // leaves `phase == .loaded` (restored from cache), so keying off `.idle` alone would never
        // re-fetch live data on the next appearance.
        .task { if !offscreen, !model.hasLiveResult { await model.load() } }
        // One respond model per recommendation: rebuilt only when the loaded gate's answer changes,
        // never per body evaluation (the model carries in-flight/pending state).
        .onChange(of: model.gate?.recommendation, initial: !offscreen) { _, recommendation in
            gateRespondModel = recommendation.flatMap(makeGateRespondModel)
        }
        .animation(JIMotion.standard, value: model.phase)
        .animation(JIMotion.standard, value: model.morningState)
        // §9 Coach overlay: in the morning flow ✕ / swipe-down = `coachAcknowledged`; re-opened
        // from the summary line it is read-only (dismiss only closes it, nothing advances).
        .overlay(alignment: .bottom) {
            if model.phase == .loaded, model.morningState == .coach || showMorningReview {
                CoachOverlayCard(change: coachContent.change) {
                    if model.morningState == .coach { model.morningEvent(.coachAcknowledged) }
                    showMorningReview = false
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
                .readableColumn()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { coachCardHeight = $0 }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(JIMotion.standard, value: showMorningReview)
        .environment(\.gateRespondModel, gateRespondModel)
        .onChange(of: model.morning?.verdictOverride, initial: true) { _, fresh in
            // A fresher `/morning` re-seeds the device's view of the call — except while this
            // device's own write is only queued and the hub has not seen it yet.
            guard let verdictOverrideModel else { return }
            if fresh != nil || verdictOverrideModel.phase != .queued { verdictOverrideModel.seed(fresh) }
        }
    }

    /// The state the screen is actually showing: Decide only once loaded (loading / error keep the title).
    private var shownMorningState: TodayMorningState { model.phase == .loaded ? model.morningState : .day }

    /// W-B57b (B-62): the call in effect for the verdict date — this device's latest write, else
    /// the hub's row from `/morning`.
    private var currentOverride: VerdictOverride? {
        overrideForVerdictDate(verdictOverrideModel?.current ?? model.morning?.verdictOverride, verdictDate: model.verdictDate)
    }

    /// The verdict as the user decided it (`effectiveVerdict`) — what Day and the summary line show.
    private var shownVerdict: VerdictParts { effectiveVerdictParts(parts: model.verdict, override: currentOverride) }

    @ViewBuilder
    private var dayContent: some View {
        // W-FIX3 BUG-28 (board 02, `daySections`): title line → NEXT → Fuel today → Tonight → the
        // EditToday squares → footer. The old hero, rings, raw insight, Felt row, EA and Mind are gone.
        // W-FIX2 DEV-03: the newer of the hub's last sync and this app's last 2xx HealthKit upload.
        HStack { Spacer(); SyncedPill(date: model.syncedAt) }.accessibilityIdentifier("today.day.synced")
        MorningSummaryLine(verdict: shownVerdict, readiness: model.readiness,
                           caption: currentOverride.flatMap { effectiveVerdict(parts: model.verdict, override: $0).wasCaption },
                           override: currentOverride) {
            showMorningReview = true
        }
        nextCard
        fuelCard
        tonightCard
        // W-FIX2 fixer BUG-19: the grid gets every square EditToday lists (`gridChips`), not the four.
        TodayGrid(chips: model.gridChips, prefs: model.tileOrderStore, onSelectKpi: onSelectKpi)
        // B-57 W1: the Trends card became a full screen, reached from this footer link.
        HStack {
            Group {
                if let onOpenTrends {
                    Button(action: onOpenTrends) { footerLabel("Trends") }
                } else {
                    NavigationLink {
                        TrendsView(recovery: model.recovery, daily: model.gate?.daily ?? [], averages: model.gate?.averages, onSelectKpi: onSelectKpi)
                    } label: { footerLabel("Trends") }
                }
            }
            .buttonStyle(.pressableScale)
            .accessibilityIdentifier("today.footer.trends")
            Spacer()
            // Board 02 "Week review": the weekly gate (nutrition, rules, the weekly answer) lives on the rationale.
            if rationaleModel != nil {
                Button { showWeekReview = true } label: { footerLabel("Week review") }
                    .buttonStyle(.pressableScale)
                    .accessibilityIdentifier("today.footer.weekReview")
            }
        }
        .navigationDestination(isPresented: $showWeekReview) {
            if let rationaleModel { gateRationaleScreen(model: rationaleModel, respondModel: gateRespondModel) }
        }
        // W-FIX3 C-g: room for the Coach card's real height, so the last squares and the footer
        // scroll out from under it (a fixed 140 pt left them unreachable behind a taller card).
        if model.morningState == .coach || showMorningReview {
            Color.clear.frame(height: todayCoachScrollReserve(cardHeight: coachCardHeight)).accessibilityHidden(true)
        }
    }

    private func footerLabel(_ text: String) -> some View {
        Text(text).jiFont(.subheadline, weight: .semibold).underline().foregroundStyle(theme.color(.info))
            .frame(minHeight: 44)
    }

    private func dayCardHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).jiFont(.footnote).foregroundStyle(theme.color(.muted)) }
        }
    }

    /// Board 02 NEXT: the session, the amber trim when there is one, and what the phone does not have yet.
    private var nextCard: some View {
        let card = dayNextCard(verdict: model.verdict, sessionForToday: model.morning?.sessionForToday, override: currentOverride)
        return Surface(level: 1, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT").jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.info))
                Text(card.session).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                if let prescription = card.prescription {
                    Text(prescription).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let exercises = card.exercises {
                    Text(exercises).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.day.next")
    }

    /// Board 02 Fuel today: today's food row (or the latest real one, named by its day), then the
    /// planned lunch, which has no source on the phone yet.
    private var fuelCard: some View {
        let fuel = dayFuel(daily: model.gate?.daily ?? [], today: todayDateString)
        return Surface(level: 1, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                dayCardHeader("Fuel today", trailing: fuel.asOf)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(jiValueText(fuel.kcal, decimals: 0)).jiNumeral(.numeralMedium, weight: .heavy)
                        .foregroundStyle(theme.color(fuel.kcal == nil ? .muted : .kcal))
                    Text(fuel.kcal == nil ? JIMissingReason.noData.rawValue
                         : fuel.kcalGoal.map { "/ \(jiNumber($0, 0)) kcal" } ?? "kcal")
                        .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Columns(minimum: 88, spacing: 12) {
                    macro("Protein", fuel.protein, role: .protein)
                    macro("Carbs", fuel.carbs, role: .carbs)
                    macro("Fat", fuel.fat, role: .fat)
                }
                Divider().overlay(theme.color(.hairlineNested))
                Text(dayPlannedLunchText).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.day.plannedLunch")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.day.fuel")
    }

    private func macro(_ label: String, _ value: Double?, role: JIColorRole) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(jiValueText(value, decimals: 0)).jiFont(.body, weight: .bold).foregroundStyle(theme.color(value == nil ? .muted : role))
                if value != nil { Text("g").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
            }
            Text(value == nil ? "\(label) · \(JIMissingReason.noData.rawValue)" : label).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Board 02 Tonight: the sleep goal the morning call uses, and last night against it.
    private var tonightCard: some View {
        let t = dayTonight(signals: model.morning?.gateSignals, recovery: model.recovery, now: Date())
        return Surface(level: 1, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                dayCardHeader("Tonight")
                Text(t.goalText).jiFont(.body, weight: .semibold).foregroundStyle(theme.color(.text))
                    .fixedSize(horizontal: false, vertical: true)
                Text(t.lastNightText).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.day.tonight")
    }

    /// B-57 §9 Coach: the one change for today, built from the DTOs this screen already holds.
    private var coachContent: CoachContent {
        CoachContentBuilder.build(morning: model.morning, gate: model.gate, recovery: model.recovery)
    }

    private var todayDateString: String { String(Date().ISO8601Format().prefix(10)) }

    private var loading: some View {
        Surface(level: 1, padding: 20) {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(width: 160, height: 44); SkeletonBlock(width: 240); SkeletonBlock(height: 90) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityLabel(msg)
                HStack {
                    Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                        .accessibilityLabel("Retry")
                        .accessibilityIdentifier("today.retry")
                    Button("Connection…", action: onOpenConnection).buttonStyle(.pressableScale).tint(theme.color(.info))
                        .accessibilityLabel("Connection…")
                        .accessibilityIdentifier("today.connection")
                }
            }
        }
    }
}

/// W-FIX3 C-g: the room kept under Day's content while the Coach card is up — its measured height
/// plus a gap; never less than the old 140 pt before the card has been measured.
public nonisolated func todayCoachScrollReserve(cardHeight: CGFloat) -> CGFloat { max(140, cardHeight + 16) }

// MARK: - W-FIX3 BUG-28 Day (board 02)

public nonisolated enum DaySection: Equatable, Sendable { case title, next, fuel, tonight, squares, footer }
/// Board 02's Day, top to bottom. No hero, rings, raw insight, Felt row, EA tile or Mind row.
public nonisolated let daySections: [DaySection] = [.title, .next, .fuel, .tonight, .squares, .footer]

public nonisolated struct DayNextCard: Equatable, Sendable {
    public let session: String
    public let prescription: String?
    /// What the phone cannot show yet (exercises, working weights) — said, never invented.
    public let exercises: String?
}

/// `verdict` is the hub's verdict; the user's call (`override`) decides what shows.
public nonisolated func dayNextCard(verdict: VerdictParts, sessionForToday: String?, override: VerdictOverride?) -> DayNextCard {
    let shown = effectiveVerdictParts(parts: verdict, override: override)
    if TodayMorningFlow.isRestDay(shown) { return DayNextCard(session: "Rest day", prescription: nil, exercises: nil) }
    let session = override != nil && !shown.session.isEmpty ? shown.session
        : decideSessionRowText(sessionForToday: sessionForToday, verdict: shown).detail
    return DayNextCard(session: session, prescription: decidePrescriptionLine(verdict: verdict, override: override),
                       exercises: "Exercises and weights — \(JIMissingReason.noData.rawValue)")
}

public nonisolated struct DayFuel: Equatable, Sendable {
    public let kcal, kcalGoal, protein, carbs, fat: Double?
    /// "as of Sep 24" when today has no food yet and the latest real day is shown; nil = today.
    public let asOf: String?
}

/// Today's food row from the gate's daily rows (`resolveTodayRow`): nil stays nil, never 0.
public nonisolated func dayFuel(daily: [DailyKpiRow], today: String) -> DayFuel {
    let row = resolveTodayRow(daily.sorted { $0.date > $1.date }).row
    func v(_ key: String) -> Double? { row.flatMap { $0.values[key] ?? nil } }
    let hasFood = v("kcal_consumed") != nil || v("protein_g") != nil
    return DayFuel(kcal: v("kcal_consumed"), kcalGoal: v("kcal_goal"), protein: v("protein_g"), carbs: v("carbs_g"), fat: v("fat_g"),
                   asOf: hasFood ? kpiAsOfLabel(valueDate: row?.date, today: today) : nil)
}

/// Board 02: no planned-meal source reaches the phone yet (B-57 W1 spec gap) — said, not faked.
public nonisolated let dayPlannedLunchText = "Planned lunch · \(JIMissingReason.notInHealthYet.rawValue)"

public nonisolated struct DayTonight: Equatable, Sendable { public let goalText, lastNightText: String }

/// Board 02 Tonight: the sleep goal the morning call gates on (`sleep_h`) and last night's length
/// (≤ 36 h old, else "—"). No bedtime: nothing on the phone knows one.
public nonisolated func dayTonight(signals: [GateSignal]?, recovery: [RecoveryDay], now: Date) -> DayTonight {
    let missing = "— \(JIMissingReason.noData.rawValue)"
    let goal = signals?.first { $0.key == "sleep_h" }.map { "\(decideCompactNumber($0.threshold)) h" }
    let night = recovery.sorted { $0.date > $1.date }.first { $0.sleepDurationSec != nil }
        .flatMap { KpiMetrics.isLastNightFresh(nightDate: $0.date, now: now) ? $0.sleepDurationSec : nil }
    return DayTonight(goalText: "Sleep goal \(goal ?? missing)",
                      lastNightText: "Last night \(night.map { "\(jiNumber($0 / 3600, 1)) h" } ?? missing)")
}

/// W-FIX3 BUG-30 (board 01): Decide has no page title — its card's date line is the only heading.
/// Coach and Day keep the page name (EditToday's `today.pageName`).
public nonisolated func todayNavigationTitle(state: TodayMorningState, pageName: String) -> String {
    state == .decide ? "" : pageName
}

/// The date subtitle rides with the title: hidden on Decide, shown on Coach / Day.
public nonisolated func todayNavigationSubtitleShown(state: TodayMorningState) -> Bool { state != .decide }

/// §4b: a Today ring is only ever drawn for a metric with a real, bounded scale — a 0–100 score or
/// a count against a goal. Everything else (HRV, RHR, ACWR, weight, macros) is baseline-relative
/// and stays a number, never a ring. `nil` = "no ring for this KPI".
public nonisolated func todayKpiRingMax(_ id: KpiMetricId) -> Double? {
    switch id {
    case .sleep, .readiness, .bodyBattery: 100
    case .steps: todayStepsGoal
    case .hrv, .rhr, .acwr, .weight, .kcal, .protein, .carbs, .fat: nil
    }
}

/// The ring tint per KPI — inside the non-reserved set (rule 6 keeps go/danger for the verdict).
public nonisolated func todayKpiRingRole(_ id: KpiMetricId) -> JIColorRole {
    switch id {
    case .sleep: .sleep
    case .steps: .info
    default: .reduced
    }
}

/// §4b: Steps is a bounded ring only against a goal. The hub carries no per-day step goal yet, so
/// the ring uses the oracle's default target; a hub-supplied goal replaces this constant when one
/// lands (P-goals).
public nonisolated let todayStepsGoal: Double = 8_000

/// The number under a Today ring — a whole, grouped figure (a 0–100 score or a step count).
public nonisolated func todayRingValueText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
}


/// B-46 item 3 (fixer): the My-KPI cell's VoiceOver sentence, pure so a host test can assert the
/// as-of day is announced and not merely computed.
nonisolated func todayKpiCellAccessibilityLabel(label: String, value: Double?, decimals: Int, unit: String, asOf: String?) -> String {
    guard let value else { return "\(label), no data yet" }
    let number = value.formatted(.number.precision(.fractionLength(decimals)))
    return [label, number, unit.isEmpty ? nil : unit, asOf].compactMap { $0 }.joined(separator: " ")
}

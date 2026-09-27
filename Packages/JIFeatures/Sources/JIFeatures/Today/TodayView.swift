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
    /// W-FIX3 BUG-28: board 02's "Week review" footer link opened the gate rationale; W-FIX5 W5-4:
    /// it opens "Your week" (its "3 of 4 sessions" value is that screen's count).
    @State private var showWeekReview = false
    @State private var weekModel: TrainingViewModel?
    @State private var showEditToday = false
    @Environment(\.nutritionGoals) private var nutritionGoals
    @Environment(\.dynamicTypeSize) private var typeSize
    /// W-FIX3 C-g: the Coach card's measured height (it grows with type size and its sentence).
    @State private var coachCardHeight: CGFloat = 0
    @Environment(\.gateRationaleModel) private var rationaleModel
    /// W-B57b (B-62): Decide's Go / Adjust write, built by the App (nil = Go just advances).
    @Environment(\.verdictOverrideModel) private var verdictOverrideModel
    @Environment(\.jiTheme) private var theme
    /// B-33 §8.5: no hub fetch and no model rebuild while the sweep renders this screen.
    @Environment(\.jiOffscreenRender) private var offscreen
    @Environment(\.recoveryInsight) private var recoveryInsight
    /// B-57 W5 C4: the progression rule's lifts and this week's plan (nil in previews → not shown).
    @Environment(\.progression) private var progression
    @Environment(\.trainingWeekSummary) private var week
    /// B-57 W5 DEV-10: the user's zones and cap for the cardio line (optional, never a default).
    @Environment(\.gateSettings) private var gateSettings

    public init(model: TodayViewModel, onOpenConnection: @escaping () -> Void, onSelectKpi: @escaping (String) -> Void = { _ in },
                onOpenTrends: (() -> Void)? = nil,
                makeGateRespondModel: @escaping (GateRecommendation) -> GateRespondViewModel? = { _ in nil }) {
        self.model = model; self.onOpenConnection = onOpenConnection; self.onSelectKpi = onSelectKpi
        self.onOpenTrends = onOpenTrends
        self.makeGateRespondModel = makeGateRespondModel
    }

    public var body: some View {
        screen
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
                // W-GUI T4 (mockup 12): the change, the signals it cites, and — re-opened from the
                // summary line — the time of the call (the override's own timestamp).
                CoachOverlayCard(change: coachContent.change, note: coachOverlayNote(coachContent),
                                 time: showMorningReview ? coachCallTime(currentOverride?.createdAt) : nil) {
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

    /// W-FIX4 PF-01: Decide is its own screen (its Go / Adjust bar is pinned above the floating tab
    /// bar); Coach and Day scroll as one column.
    @ViewBuilder
    private var screen: some View {
        if model.phase == .loaded, model.morningState == .decide {
            // B-57 §2: Decide → Coach → Day, advanced only by what the user does and kept per
            // verdict date (`TodayViewModel.morningState`).
            DecideView(verdict: model.verdict, readiness: model.readiness,
                       syncing: model.morning?.verdict == nil,
                       gateSignals: model.morning?.gateSignals,
                       verdictDate: model.verdictDate,
                       sessionForToday: model.morning?.sessionForToday,
                       override: currentOverride,
                       overrideModel: verdictOverrideModel,
                       syncedAt: model.syncedAt,
                       normals: decideSignalNormals(recovery: model.recovery),
                       banner: StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)) { model.morningEvent(.gateResponded) }
        } else {
            ScreenScroll {
                VStack(alignment: .leading, spacing: 16) {
                    StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                    switch model.phase {
                    case .idle, .loading: loading
                    case .error(let msg): errorCard(msg)
                    case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                        .accessibilityLabel("No data yet — run a sync on the hub.")
                    // §9: Coach is the Day view plus a bottom overlay card (below), not a step.
                    case .loaded: dayContent
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
                .readableColumn()
            }
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
        // W-GUI T3 (mockup 02): the summary line is the ONE tinted card of the Day.
        Surface(level: 1, padding: JISpacing.s3, tint: theme.color(verdictColorRole(shownVerdict.tone))) {
            MorningSummaryLine(verdict: shownVerdict, readiness: model.readiness,
                               caption: currentOverride.flatMap { effectiveVerdict(parts: model.verdict, override: $0).wasCaption },
                               override: currentOverride) {
                showMorningReview = true
            }
        }
        JISectionHeader("Next")
        nextCard
        HStack(alignment: .firstTextBaseline) {
            JISectionHeader(dayFuelTitle(asOf: dayFuel(daily: model.gate?.daily ?? [], today: todayDateString).asOf))
            Spacer(minLength: JISpacing.s2)
            if let asOf = dayFuel(daily: model.gate?.daily ?? [], today: todayDateString).asOf {
                Text(asOf).jiFont(.caption).foregroundStyle(theme.color(.muted)).padding(.trailing, JISpacing.s4)
            }
        }
        fuelCard
        JISectionHeader("Tonight")
        tonightCard
        HStack(alignment: .center) {
            JISectionHeader("Your squares")
            Spacer(minLength: JISpacing.s2)
            // W-GUI T3 (report §7 rule 2): Edit is a glass round button, never a text link.
            JIGlassButton("pencil", label: "Edit Today") { showEditToday = true }
                .padding(.trailing, JISpacing.s1)
                .accessibilityIdentifier("today.day.edit")
        }
        // W-FIX2 fixer BUG-19: the grid gets every square EditToday lists (`gridChips`), not the four.
        // W-DATA fixer R9: the Load square takes the gate-input load (minutes + band) when no ACWR.
        TodayGrid(chips: todayChipsWithLoad(model.gridChips, load: recoveryInsight?.loadReading), prefs: model.tileOrderStore, onSelectKpi: onSelectKpi)
            .task { if !offscreen { await recoveryInsight?.refreshIfStale() } }
        // W-GUI T3 (DEV-07, mockup 02): Trends / Week review are chevron rows in one grouped card,
        // never underlined text. BUG-13 (router push) and BUG-28 (weekly gate) routes unchanged.
        Surface(level: 1, padding: 0) {
            VStack(spacing: 0) {
                Group {
                    if let onOpenTrends {
                        Button(action: onOpenTrends) { dayFooterRow(.trends) }
                    } else {
                        NavigationLink {
                            TrendsView(recovery: model.recovery, daily: model.gate?.daily ?? [], averages: model.gate?.averages, onSelectKpi: onSelectKpi)
                        } label: { dayFooterRow(.trends) }
                    }
                }
                .buttonStyle(.pressableScale)
                .accessibilityIdentifier("today.footer.trends")
                // W-FIX5 W5-4: "Week review" opens Your week (the rationale only without a training provider).
                if weekReviewDestination != nil {
                    JIRowDivider()
                    Button {
                        if weekReviewDestination == .yourWeek, weekModel == nil { weekModel = model.makeTrainingWeekModel() }
                        showWeekReview = true
                    } label: { dayFooterRow(.weekReview) }
                        .buttonStyle(.pressableScale)
                        .accessibilityIdentifier("today.footer.weekReview")
                }
            }
            .padding(.vertical, 6).padding(.horizontal, JISpacing.s4)
        }
        .sheet(isPresented: $showEditToday) {
            NavigationStack {
                EditTodayView(model: EditTodayViewModel(prefs: model.tileOrderStore, chips: model.gridChips)) { showEditToday = false }
            }
            .jiSheetGround()
        }
        .navigationDestination(isPresented: $showWeekReview) {
            if let weekModel {
                TrainingWeekView(model: weekModel).task { await weekModel.load() }
            } else if let rationaleModel {
                gateRationaleScreen(model: rationaleModel, respondModel: gateRespondModel)
            }
        }
        // W-FIX3 C-g: room for the Coach card's real height, so the last squares and the footer
        // scroll out from under it (a fixed 140 pt left them unreachable behind a taller card).
        if model.morningState == .coach || showMorningReview {
            Color.clear.frame(height: todayCoachScrollReserve(cardHeight: coachCardHeight)).accessibilityHidden(true)
        }
    }

    private var weekReviewDestination: DayWeekReviewDestination? {
        dayWeekReviewDestination(hasWeekModel: !offscreen && (weekModel != nil || model.makesTrainingWeekModel),
                                 hasRationale: rationaleModel != nil)
    }

    /// W-GUI T3: the footer rows (mockup 02) — a chevron row each, with the mockup's subtitle
    /// as the value slot; Week review's count is not on the phone (plan §B: W5) → "—".
    private func dayFooterRow(_ row: DayFooterRow) -> some View {
        // B-57 W5: Week review's value is the week's count ("1 of 4 sessions") once it is known.
        JIChevronRow(title: row.title, value: row == .weekReview ? dayWeekReviewValue(week) : row.value, systemImage: row.systemImage)
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
        let card = dayNextCard(verdict: model.verdict, sessionForToday: model.morning?.sessionForToday, override: currentOverride,
                               plan: model.exercises, weekday: model.todayWeekday,
                               zones: gateSettings.zones, capBpm: gateSettings.hrCapBpm)
        let template = dayNextTemplate(card: card)
        // B-57 W5 C4: the rule's lifts for the plan session the rows came from.
        let lifts = card.rows.isEmpty ? [] : (progression?.lifts(forSession: card.plannedSession ?? todaysStrengthSession(week)) ?? [])
        return Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 6) {
                // W-GUI T3 (DEV-10 GUI half, mockup 02): the card's title row names the session with
                // its kind's symbol; the two templates (strength = exercise rows, cardio = the
                // prescription) key off the existing PF-02 plan match — no new rule.
                HStack(spacing: JISpacing.s2) {
                    Image(systemName: template.systemImage)
                        .foregroundStyle(theme.color(.info)).accessibilityHidden(true)
                    Text(card.session).jiFont(.cardTitle, weight: .bold).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // B-57 W5 (board 1/02): "Session 2 of 4 this week" while today's session is still to do.
                if !card.rows.isEmpty, let ordinal = daySessionOrdinal(week) {
                    Text("\(ordinal.prefix(1).uppercased())\(ordinal.dropFirst()) this week")
                        .jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                        .accessibilityIdentifier("today.day.next.ordinal")
                }
                if let prescription = card.prescription {
                    Text(prescription).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // W-FIX4 PF-02: the plan's exercises and weights, as Training lists them.
                ForEach(card.rows) { row in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { nextRowName(row); Spacer(minLength: 8); nextRowLoad(row, lifts: lifts) }
                        VStack(alignment: .leading, spacing: 2) { nextRowName(row); nextRowLoad(row, lifts: lifts) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("today.day.next.exercise.\(row.id)")
                }
                if let exercises = card.exercises {
                    Text(exercises).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
                // B-57 W5 DEV-10: the cardio part's line (Zone 2 / intervals) from the user's zones and cap.
                if let cardio = card.cardio {
                    Text(cardio).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.day.next.cardio")
                }
                // B-57 W5 C4 (board 1/02): "Progression due on …" when the rule says so; nothing otherwise.
                if let callout = dayProgressionCallout(lifts) {
                    DayProgressionCalloutView(callout: callout).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.day.next")
        .task { if !offscreen { await progression?.refreshIfNeeded() } }
    }

    private func nextRowName(_ row: TrainingHeroRow) -> some View {
        Text(row.name).jiFont(.footnote, weight: .semibold).foregroundStyle(theme.color(.text))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func nextRowLoad(_ row: TrainingHeroRow, lifts: [LiftProgression]) -> some View {
        let load = dayNextRowLoad(row, lifts: lifts)
        return Text(load.text).jiFont(.footnote, weight: load.due ? .semibold : .regular)
            .foregroundStyle(theme.color(load.due ? .go : .muted)).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Board 02 Fuel today: today's food row (or the latest real one, named by its day), then the
    /// planned lunch, which has no source on the phone yet.
    private var fuelCard: some View {
        let fuel = dayFuel(daily: model.gate?.daily ?? [], today: todayDateString)
        // W-GUI T3 (mockup 02): kcal + goal + "n left · your goal", the kcal ring against the goal
        // (only when a goal exists — no ring for a missing goal), three macro tiles of ONE size
        // (JITile .macroTile) with a goal tick only where the user set one (W2 `nutritionGoals`),
        // then the planned-lunch row. The "as of" date is the intake row's own date (DEV-11 stays data).
        return Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: JISpacing.s3) {
                // R-SIM fix: at AX sizes the ring drops under the numeral instead of squeezing it to "1…".
                let heroLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: JISpacing.s2)) : AnyLayout(HStackLayout(alignment: .center, spacing: JISpacing.s3))
                heroLayout {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(jiValueText(fuel.kcal, decimals: 0)).jiNumeral(.numeralMedium, weight: .heavy)
                                .foregroundStyle(theme.color(fuel.kcal == nil ? .muted : .kcal))
                                .lineLimit(1).minimumScaleFactor(0.6).fixedSize()
                            Text(fuel.kcal == nil ? JIMissingReason.noData.rawValue
                                 : fuel.kcalGoal.map { "/ \(jiNumber($0, 0)) kcal" } ?? "kcal")
                                .jiFont(.footnote).foregroundStyle(theme.color(.muted))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let left = dayFuelLeftText(kcal: fuel.kcal, goal: fuel.kcalGoal, isToday: fuel.asOf == nil) {
                            Text(left).jiFont(.caption, weight: .semibold).foregroundStyle(theme.color(.muted))
                        }
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    if let kcal = fuel.kcal, let goal = fuel.kcalGoal, goal > 0 {
                        ZStack {
                            ScoreRing(value: kcal, max: goal, tint: theme.color(.kcal), size: 56)
                            Text(jiNumber(min(kcal / goal, 9.99) * 100, 0) + "%").jiFont(.caption, weight: .bold).foregroundStyle(theme.color(.text))
                        }
                        .accessibilityHidden(true)
                    }
                }
                HStack(spacing: JISpacing.tileGap) {
                    macroTile("Protein", fuel.protein, role: .protein, goal: nutritionGoals.goal(for: .protein))
                    macroTile("Carbs", fuel.carbs, role: .carbs, goal: nutritionGoals.goal(for: .carbs))
                    macroTile("Fat", fuel.fat, role: .fat, goal: nutritionGoals.goal(for: .fat))
                }
                JIRowDivider().padding(.leading, 0)
                Text(dayPlannedLunchText).jiFont(.footnote).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.day.plannedLunch")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.day.fuel")
    }

    /// One macro tile (mockup 02 `nested tile`): the number, "Protein · goal 155" or just the name
    /// when no goal is set (never "no goal" as a claim), and a goal bar only with a goal.
    private func macroTile(_ label: String, _ value: Double?, role: JIColorRole, goal: Double?) -> some View {
        JITile(family: .macroTile) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(jiValueText(value, decimals: 0)).jiNumeral(.numeralSmall, tint: value == nil ? .muted : role)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if value != nil { Text("g").jiFont(.caption).foregroundStyle(theme.color(.muted)) }
                }
                Text(dayMacroCaption(label: label, value: value, goal: goal)).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let goal, goal > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.color(.nested))
                            if let value { Capsule().fill(theme.color(role)).frame(width: max(4, min(1, value / goal) * g.size.width)) }
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(dayMacroCaption(label: label, value: value, goal: goal) + (value.map { ", \(jiNumber($0, 0)) g" } ?? ", no data"))
    }

    /// Board 02 Tonight: the sleep goal the morning call uses, and last night against it.
    private var tonightCard: some View {
        let t = dayTonight(signals: model.morning?.gateSignals, recovery: model.recovery, now: Date())
        return Surface(level: 1, padding: JISpacing.cardPadding) {
            VStack(alignment: .leading, spacing: 6) {
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
    /// W-FIX4 PF-02: the session's exercises and working weights from the hub's plan
    /// (`/planning/exercises`, the rows Training lists) — empty on a rest day or with no plan rows.
    public let rows: [TrainingHeroRow]
    /// What the phone cannot show (no plan rows for this session) — said, never invented; nil
    /// when `rows` carries the exercises or on a rest day.
    public let exercises: String?
    /// B-57 W5 DEV-10: a cardio part's line ("Zone 2 · 60 min · 117–138 bpm", "Intervals · 4 × 4 min").
    public var cardio: String? = nil
    /// B-57 W5: the plan session the rows came from — the progression lifts are read for it.
    public var plannedSession: String? = nil
    /// W-B57-W5 fixer (DEV-10): the verdict is a rest day — the card's symbol is not a runner.
    public var isRest = false
}

/// W-FIX4 PF-02: today's session in the plan — by name first (the hub's `session_for_today` or the
/// verdict's session, which may carry extras: "Day 3 Full Upper + Z2 60min"), else the session
/// assigned to today's weekday (Mon = 0), as Training picks it.
public nonisolated func dayPlannedSession(names: [String?], plan: [Exercise], weekday: Int?) -> PlannedSession? {
    func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
    let wanted = names.compactMap { $0 }.map(norm).filter { !$0.isEmpty }
    let sessions = plan.reduce(into: [Exercise]()) { acc, e in if !acc.contains(where: { $0.sessionName == e.sessionName }) { acc.append(e) } }
    let byName = sessions
        .filter { e in let n = norm(e.sessionName); return !n.isEmpty && wanted.contains { $0 == n || $0.contains(n) } }
        .max { norm($0.sessionName).count < norm($1.sessionName).count }
    let picked = byName ?? weekday.flatMap { w in plan.first { $0.weekday == w } }
    return picked.map { PlannedSession(id: $0.sessionId ?? -1, name: $0.sessionName, weekday: $0.weekday ?? -1) }
}

/// `verdict` is the hub's verdict; the user's call (`override`) decides what shows.
/// B-57 W5 DEV-10: a cardio session (Zone 2, intervals) gets its line from the user's zones and cap
/// (both optional — never a default) instead of "Exercises and weights — No data".
public nonisolated func dayNextCard(verdict: VerdictParts, sessionForToday: String?, override: VerdictOverride?,
                                    plan: [Exercise] = [], weekday: Int? = nil,
                                    zones: HrZones? = nil, capBpm: Int? = nil) -> DayNextCard {
    let shown = effectiveVerdictParts(parts: verdict, override: override)
    if TodayMorningFlow.isRestDay(shown) { return DayNextCard(session: "Rest day", prescription: nil, rows: [], exercises: nil, isRest: true) }
    let session = override != nil && !shown.session.isEmpty ? shown.session
        : decideSessionRowText(sessionForToday: sessionForToday, verdict: shown).detail
    let planned = dayPlannedSession(names: [sessionForToday, shown.session, verdict.session], plan: plan, weekday: weekday)
    let rows = trainingHeroRows(exercises: plan, session: planned)
    let cardio = dayCardioLine(session: session, zones: zones, capBpm: capBpm)
    let saysNoData = rows.isEmpty && (cardio == nil || daySessionHasStrengthPart(session))
    return DayNextCard(session: session, prescription: decidePrescriptionLine(verdict: verdict, override: override), rows: rows,
                       exercises: saysNoData ? "Exercises and weights — \(JIMissingReason.noData.rawValue)" : nil,
                       cardio: cardio, plannedSession: rows.isEmpty ? nil : planned?.name)
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

/// Board 02: meal plans live on the hub (`/meals`), which the phone does not read yet — said with
/// the true reason (W-FIX4 PF-10: never "Not in Health yet"; Health has no meal plans), not faked.
public nonisolated let dayPlannedLunchText = "Planned lunch — meal plan not on the phone yet"

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


// MARK: - W-GUI T3 (mockup 02) pure helpers

/// The NEXT card's two templates: strength (the plan's exercise rows, PF-02) or cardio (the
/// prescription). Keyed on the existing PF-02 match — rows found = a strength session.
public nonisolated enum DayNextTemplate: Sendable, Equatable {
    case strength, cardio, rest
    /// The title row's symbol: dumbbell / runner / moon — the runner only for a cardio session.
    public var systemImage: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .cardio: "figure.run"
        case .rest: "moon.zzz.fill"
        }
    }
}
public nonisolated func dayNextTemplate(rows: [TrainingHeroRow]) -> DayNextTemplate { rows.isEmpty ? .cardio : .strength }

/// W-B57-W5 fixer (DEV-10): the template from the whole card — a rest day is `.rest`, a session
/// with plan rows OR a strength part (even without rows on the phone) is `.strength`; the runner
/// only for a cardio-only session.
public nonisolated func dayNextTemplate(card: DayNextCard) -> DayNextTemplate {
    if card.isRest { return .rest }
    if !card.rows.isEmpty || daySessionHasStrengthPart(card.session) { return .strength }
    return .cardio
}

/// "434 left · your goal" from the intake and the goal already on the row; nil without both.
/// W-DATA fixer R1 (DEV-11): "left" only for today's row — an earlier day (the latest logged one)
/// is a finished day: "752 under your goal" / "83 over your goal", never "left" today.
public nonisolated func dayFuelLeftText(kcal: Double?, goal: Double?, isToday: Bool = true) -> String? {
    guard let kcal, let goal, goal > 0 else { return nil }
    let left = goal - kcal
    guard isToday else { return left >= 0 ? "\(jiNumber(left, 0)) under your goal" : "\(jiNumber(-left, 0)) over your goal" }
    return left >= 0 ? "\(jiNumber(left, 0)) left · your goal" : "\(jiNumber(-left, 0)) over · your goal"
}

/// W-DATA fixer R1 (DEV-11): the Fuel section title says "today" only for today's food row; an
/// earlier logged day (`DayFuel.asOf` set, shown beside it) is "Fuel · last logged".
public nonisolated func dayFuelTitle(asOf: String?) -> String { asOf == nil ? "Fuel today" : "Fuel · last logged" }

/// "Protein · goal 155" with a user goal; the bare name without one (no "no goal" claim); the
/// reason word when the value is missing.
public nonisolated func dayMacroCaption(label: String, value: Double?, goal: Double?) -> String {
    if value == nil { return "\(label) · \(JIMissingReason.noData.rawValue)" }
    if let goal, goal > 0 { return "\(label) · goal \(jiNumber(goal, 0))" }
    return label
}

/// The Day's footer rows (mockup 02): chevron rows, never text links (DEV-07).
/// W-FIX5 W5-4: where Day's "Week review" row goes — Your week whenever a training provider is
/// there; the gate rationale only without one; no row with neither.
public nonisolated enum DayWeekReviewDestination: Sendable, Equatable { case yourWeek, rationale }

public nonisolated func dayWeekReviewDestination(hasWeekModel: Bool, hasRationale: Bool) -> DayWeekReviewDestination? {
    hasWeekModel ? .yourWeek : (hasRationale ? .rationale : nil)
}

public nonisolated enum DayFooterRow: Sendable, Equatable, CaseIterable {
    case trends, weekReview
    public var title: String { self == .trends ? "Trends" : "Week review" }
    public var systemImage: String { self == .trends ? "chart.xyaxis.line" : "calendar" }
    /// The subtitle slot: Trends' scope; Week review's "n of 4 sessions" is not on the phone (W5) → "—".
    public var value: String { self == .trends ? "28-day normal bands" : "— not counted yet" }
}

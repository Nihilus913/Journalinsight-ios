import SwiftUI
import JICore
import JICompute
import JIDesign
import JIPersistence
import JIWorkouts

/// Training screen (W3a-L3, frozen contract `TrainingView.init(model:)`). Composes the week/day
/// strips, gate summary, session-coach entry, day detail, and lift steppers — oracle:
/// `mobile/app/(tabs)/training.tsx`.
public struct TrainingView: View {
    @Bindable private var model: TrainingViewModel
    @State private var showSessionCoach = false
    /// W-B38-A A-10: "Start session" offers the live coach and the set logger.
    @State private var showStartChoice = false
    @State private var strengthLog: StrengthLogViewModel?
    @State private var strengthHistory: StrengthHistoryViewModel?
    @State private var showStrengthLog = false
    @Environment(\.strengthLogDeps) private var strengthLogDeps
    @Environment(\.progression) private var progression
    /// W-B38-B: sends today's training down to the Watch (strength bridge, plan via app context).
    @Environment(\.strengthWatchPlanSender) private var sendWatchPlan
    /// W-PLANNER PL-5: "Edit week" AND the toolbar icon push the Planner (the week + every
    /// workout; the weekday assignment, B-45 (c) / B-52 outbox, lives there).
    @State private var showWeek = false
    /// W-B40 L3 (B-82): day-first — a tap on a day of the week strip opens that day's preview.
    @State private var dayPreview: TrainingDayRef?
    /// B-95 (BP-26): the pushed Time in zone screen (W / M / 6M).
    @State private var zoneTime: ZoneTimeModel?
    /// W-B98A B98-4: the completed workout whose Activity detail is pushed.
    @State private var activityDetail: ActivityDetailModel?
    /// B-90 p5: per-muscle freshness + load (card → pushed Muscles screen → detail sheet).
    @State private var muscles: MusclesModel?
    @State private var showMuscles = false
    /// B-94 (BP-4): the pushed Progress screen (strength + cardio charts).
    @State private var progressCharts: ProgressViewModel?
    /// B-33: a screen root's own token reads resolve to the theme it installs below —
    /// `.jiTheme(.native)` applies to descendants, never to the view that applies it, so reading
    /// `\.jiTheme` here would see the presenter's value rather than this screen's.
    private let theme = JITheme.native
    #if canImport(WorkoutKit)
    // B-37-L3 (P-workouts): the app wires `\.sendToWatchModel`; nil (previews, tests, no hub) hides
    // the toolbar button. Environment-routed so `init(model:)` stays the frozen contract.
    @Environment(\.sendToWatchModel) private var sendToWatch
    @State private var showSendToWatch = false
    #endif
    /// B-57 W4: the user's optional cap / zones, injected by the app shell (W-FIX5 TR-zones: also the
    /// Zones card, so it is declared outside the WorkoutKit block).
    @Environment(\.gateSettings) private var gateSettings
    /// W-FIX11 H1-05: the user's call (Decide's Adjust) — header, hero and Readiness follow it.
    @Environment(\.verdictOverrideModel) private var verdictOverrideModel
    public init(model: TrainingViewModel) { self.model = model }

    private var currentOverride: VerdictOverride? {
        guard !model.verdictIsStale else { return nil }
        return overrideForVerdictDate(verdictOverrideModel?.current ?? model.morning?.verdictOverride,
                                      verdictDate: model.morning?.verdictDate)
    }

    public var body: some View {
        ScrollViewReader { proxy in
        ScreenScroll {   // W-GUI F6: the shared scroll root (edge effect, sweep branch)
            VStack(alignment: .leading, spacing: 16) {
                // B-45 (a): the screen's own date is the REAL device day (mirrors `TodayView`).
                // W-FIX3 fixer BUG-44 (board 3/01): "Full · Wed 23 Sep" + the synced pill on one row;
                // the verdict word leads only when the hub's verdict is today's.
                TrainingSessionHeader(
                    subtitle: trainingSubtitle(verdict: model.morning?.verdict, isStale: model.verdictIsStale, date: model.todayDate, override: currentOverride),
                    fetchedAt: model.fetchedAt, watchLine: watchLine)
                StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                switch model.phase {
                case .idle, .loading: loading
                case .error(let msg): errorCard(msg)
                case .empty: Surface { Text("No data yet — run a sync on the hub.").foregroundStyle(theme.color(.muted)) }
                        .accessibilityIdentifier("training-empty")
                case .loaded: loaded
                }
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        #if DEBUG
        // W-B81 dev affordance (same family as `-training-day`): `-training-scroll this-day` scrolls
        // to the "This day" card once loaded, so a scripted run can screenshot the completed workouts.
        .task(id: model.phase) {
            guard model.phase == .loaded, let i = CommandLine.arguments.firstIndex(of: "-training-scroll"),
                  i + 1 < CommandLine.arguments.count else { return }
            let target = CommandLine.arguments[i + 1]   // "this-day" or a row id ("completed-workout-<activity id>")
            try? await Task.sleep(for: .seconds(1))
            proxy.scrollTo(target == "this-day" ? "training-this-day" : target, anchor: .top)
        }
        #endif
        }
        .jiPageGround()
        .jiTheme(.native)
        // §5: the hand-drawn large title becomes the system one, so scroll-edge and the
        // large-title collapse come from the navigation stack instead of a `VStack` header.
        .navigationTitle("Training")
        .refreshable { await model.refresh() }
        .environment(\.jiHubOffline, !model.hubReachable)   // W-FIX11 H1-15
        .task { if !model.hasLiveResult { await model.load() } }
        // W-FIX2 BUG-25: the pending glyph clears after ANY drain — on every appearance, and while
        // a weekday is queued and the screen is up (the watcher ends once nothing is pending).
        .onAppear { model.screenAppeared() }
        .task(id: model.hasPendingSync) { await model.watchPendingSync() }
        .animation(JIMotion.standard, value: model.phase)
        // W-B38-B B-8: the live source is the Watch's mirrored strength session
        // (`MirroredSessionFeed`, fed by the App's mirroring handler + strength bridge). Where no
        // Watch can mirror (`isAvailable` false) the coach keeps its honest "not available" wall.
        .navigationDestination(isPresented: $showSessionCoach) {
            SessionCoachView(model: SessionCoachViewModel(
                live: MirroredSessionFeed.shared.isAvailable ? MirroredSessionFeed.shared : nil, settings: gateSettings))
        }
        // W-B38-A A-10: the entry offers "Log sets" next to the coach (only when the app wired the
        // on-disk strength log; previews / tests keep the coach-only tap).
        .confirmationDialog("Start session", isPresented: $showStartChoice, titleVisibility: .visible) {
            Button("Log sets") { openStrengthLog() }
            Button("Live coach") { showSessionCoach = true }
        }
        // W-B38-B: today's selected training goes down to the Watch whenever it (re)loads.
        .task(id: watchPlanKey) { sendTodayPlanToWatch() }
        // B-43 P1: a rest-end notification tap (`ji://strength-log`) re-opens the logger.
        .onChange(of: StrengthLoggerOpenRequest.shared.pending, initial: true) { _, pending in
            guard pending, StrengthLoggerOpenRequest.shared.consume() else { return }
            if strengthLog != nil { showStrengthLog = true } else { openStrengthLog() }
        }
        .navigationDestination(isPresented: $showStrengthLog) {
            if let strengthLog { StrengthLogView(model: strengthLog, history: strengthHistory) }
        }
        #if canImport(WorkoutKit)
        .sheet(isPresented: $showSendToWatch) {
            if let sendToWatch { SendToWatchSheet(model: sendToWatch) }
        }
        #endif
        .navigationDestination(item: $zoneTime) { ZoneTimeChartView(model: $0) }
        // W-B98A B98-4: a completed workout on "This day" → Activity detail (splits + HR/pace).
        .navigationDestination(item: $activityDetail) { ActivityDetailView(model: $0) }
        #if DEBUG
        // B-98 dev affordance: `-activity-detail <id> [type]` pushes that activity's detail (sim screenshots).
        .task {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "-activity-detail"), i + 1 < args.count, let id = Int(args[i + 1]) else { return }
            let type = i + 2 < args.count && !args[i + 2].hasPrefix("-") ? args[i + 2] : "running"
            try? await Task.sleep(for: .seconds(2))
            activityDetail = model.makeActivityDetailModel(activity: DayActivity(activityId: id, type: type, name: nil, durationSec: nil, distanceM: nil))
        }
        #endif
        .navigationDestination(isPresented: $showMuscles) {
            if let muscles { MusclesScreen(model: muscles, initialDetail: musclesLaunchDetail()) }
        }
        .task { setUpMuscles() }
        .onAppear { muscles?.reload() }
        .navigationDestination(item: $progressCharts) { ProgressChartsView(model: $0) }
        #if DEBUG
        // B-94 dev affordance: `-progress-open` pushes Progress once Training is up (sim screenshots).
        .task {
            guard CommandLine.arguments.contains("-progress-open") else { return }
            try? await Task.sleep(for: .seconds(2))
            progressCharts = model.makeProgressModel(deps: strengthLogDeps)
        }
        #endif
        #if DEBUG
        // B-95 dev affordance: `-zone-time <W|M|6M>` pushes Time in zone at that range (sim screenshots).
        .task {
            guard let i = CommandLine.arguments.firstIndex(of: "-zone-time"), i + 1 < CommandLine.arguments.count,
                  let span = ZoneTimeSpan(rawValue: CommandLine.arguments[i + 1]) else { return }
            try? await Task.sleep(for: .seconds(2))
            zoneTime = model.makeZoneTimeModel(span: span)
        }
        #endif
        .navigationDestination(isPresented: $showWeek) { PlannerView(model: model, strengthLogDeps: strengthLogDeps, sendWatchPlan: sendWatchPlan) }
        .sheet(item: $dayPreview) { ref in
            TrainingDaySheet(model: model, weekday: ref.weekday, initialRoute: Self.launchArgumentDayRoute())
        }
        #if DEBUG
        // B-82 dev affordance (same family as `-start-tab`): `-training-day <0-6>` opens that day's
        // sheet once the screen is up; `-training-day-route pick` also pushes the picker
        // (PL-5: the library is the Planner's); `-training-day-autopick <option id>` makes that pick first — so a scripted simulator run can screenshot the flow without a tap.
        .task {
            guard let wd = Self.launchArgumentDay() else { return }
            try? await Task.sleep(for: .seconds(3))
            // `-training-day-autopick <option id>` ("s8" / "t3"): make that pick first, as a tap would.
            // W-FIX10 F10-2: the day is selected first, as a tap does (the hero follows it), so the
            // B40-V5 proof shows the hero after the change.
            if let date = model.weekSummary.days.first(where: { $0.weekday == wd })?.date { model.selectDate(date) }
            if let i = CommandLine.arguments.firstIndex(of: "-training-day-autopick"), i + 1 < CommandLine.arguments.count {
                let options = model.dayOptions(weekday: wd)
                if let o = (model.plannerOptions(weekday: wd) + options.plan + options.library).first(where: { $0.id == CommandLine.arguments[i + 1] }) {
                    _ = await model.changeDay(weekday: wd, adding: o.choice, removing: nil)
                }
            }
            // `-training-day-sheet off`: leave the sheet closed so the hero is on screen.
            if trainingLaunchDaySheetOpens() { dayPreview = TrainingDayRef(weekday: wd) }
        }
        // W-FIX10 F10-2 (B40-V6 proof): `-send-to-watch-open [t<id>]` opens the Send to Watch sheet
        // once the screen is up (that library workout picked), without a tap.
        .task {
            guard let route = trainingLaunchSendToWatch() else { return }
            try? await Task.sleep(for: .seconds(4))
            #if canImport(WorkoutKit)
            guard let sendToWatch else { return }
            if case .template(let id) = route { sendToWatch.pickOnly(id) }
            showSendToWatch = true
            #endif
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showWeek = true } label: { Image(systemName: "figure.run.square.stack") }
                    .accessibilityLabel("Planner")
                    .accessibilityHint("Your week and every workout")
                    .accessibilityIdentifier("training-open-planner")
            }
        }
    }

    static func launchArgumentDay(_ arguments: [String] = CommandLine.arguments) -> Int? {
        #if DEBUG
        guard let i = arguments.firstIndex(of: "-training-day"), arguments.index(after: i) < arguments.endIndex,
              let wd = Int(arguments[arguments.index(after: i)]), (0...6).contains(wd) else { return nil }
        return wd
        #else
        return nil
        #endif
    }

    static func launchArgumentDayRoute(_ arguments: [String] = CommandLine.arguments) -> TrainingDaySheet.Route? {
        #if DEBUG
        guard let i = arguments.firstIndex(of: "-training-day-route"), arguments.index(after: i) < arguments.endIndex else { return nil }
        switch arguments[arguments.index(after: i)] {
        case "pick": return .pick(replacing: nil)
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// B-82: a day tap selects it for "This day" AND opens its preview (day-first).
    private func openDay(_ date: String) {
        model.selectDate(date)
        if let wd = model.weekSummary.days.first(where: { $0.date == date })?.weekday { dayPreview = TrainingDayRef(weekday: wd) }
    }

    private var watchLine: String? {
        #if canImport(WorkoutKit)
        trainingWatchLine(sendToWatch?.state)
        #else
        nil
        #endif
    }

    private var loading: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) { SkeletonBlock(height: 90); SkeletonBlock(height: 60); SkeletonBlock(height: 160) }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(msg).foregroundStyle(theme.color(.text))
                    .accessibilityIdentifier("training-error")
                // W-OFFLINE2 OFF2-3: a needs-hub card has nothing to retry.
                if model.availability.offersRetry {
                    Button("Retry") { Task { await model.refresh() } }.buttonStyle(.pressableScale).tint(theme.color(.info))
                        .accessibilityLabel("Retry")
                        .accessibilityIdentifier("training-retry")
                }
            }
        }
    }

    private var loaded: some View {
        let subtitle = trainingSubtitle(verdict: model.morning?.verdict, isStale: model.verdictIsStale, date: model.todayDate, override: currentOverride)
        return VStack(alignment: .leading, spacing: 0) {
            // W-GUI TR1 (mockup 04): the week strip in a card with its legend and the plan line,
            // then "Today" = the one tinted hero (verdict colour), one primary button.
            Surface(level: 1, padding: JISpacing.cardPadding) {
                VStack(alignment: .leading, spacing: JISpacing.s2) {
                    // B-57 W5 (board 3/01): the plan week (S / I / R / –, n of N done, Edit week)
                    // replaces the kcal day strip; a tap still selects the day for "This day".
                    TrainingThisWeekStrip(summary: model.weekSummary, selectedDate: model.selectedDate,
                                          onSelect: openDay) { showWeek = true }
                    if let summary = trainingPlanSummary(sessionNames: model.planSessions.map(\.name)) {
                        Text(summary).jiFont(.caption).foregroundStyle(theme.color(.muted))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("training-plan-summary")
                    }
                }
            }
            JISectionHeader("Today")
            // W-FIX3 fixer BUG-44 (board 3/01): the hero carries the session, its exercises, Send to
            // Watch and Start session (the live session coach — no separate coach row).
            TrainingHeroCard(
                dayLabel: heroDayLabel,
                // W-PLANNER PL-6: the whole day ("Day 1 Full Upper + Zone 2 40 min"), lifts below.
                sessionName: trainingHeroTitle(day: heroDay, sessionName: model.plannedSessionForSelectedDay?.name),
                rows: trainingHeroRows(exercises: model.exercises, session: model.plannedSessionForSelectedDay),
                onSendToWatch: sendToWatchAction,
                onStart: { if strengthLogDeps == nil { showSessionCoach = true } else { showStartChoice = true } },
                showsStart: model.selectedDate != model.todayDateString || trainingHeroOffersStart(override: currentOverride),
                tint: subtitle.word == nil ? nil : trainingToneColor(subtitle.tone, theme))
            // W-FIX7 F7-1: today's session done (or another activity) from Apple Health.
            SessionCompletionLine(completion: model.selectedDayCompletion)
                .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s2)
            JISectionHeader("Readiness")
            GateDetailCard(morning: model.morning, gate: model.gate, isStale: model.verdictIsStale, override: currentOverride)
            // B-90 p5 (mockup BP-2-3): the gate answers "can I train", Muscles "what can I load".
            if let muscles, let summary = muscles.summary {
                JISectionHeader("Muscles").id("training-muscles")
                MusclesCard(summary: summary, calendar: muscles.calendar) { showMuscles = true }
            }
            JISectionHeader("This day").id("training-this-day")
            TrainingDayDetailCard(
                date: model.selectedDate,
                detail: model.dayDetail,
                plannedSession: model.plannedSessionForSelectedDay,
                healthWorkouts: model.selectedDayHealthWorkouts
            )
            .environment(\.openActivityDetail) { activityDetail = model.makeActivityDetailModel(activity: $0) }
            JISectionHeader(trainingNextStrengthHeader(weekdayWord: nil))
            LiftSteppers(exercises: model.exercises, pendingIds: model.pendingUpdates, failedIds: model.updateFailed, queuedIds: model.pendingExerciseSync) { exercise, patch in
                Task { await model.updateExercise(exerciseId: exercise.exerciseId, exerciseName: exercise.exerciseName, patch: patch) }
            }
            Text(trainingProgressionCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s3)
            // B-95 (BP-26): time in zone over weeks and months, next to the zones it is binned with.
            JISectionHeader("Zones · over time")
            Surface(level: 1, padding: 0) {
                Button { zoneTime = model.makeZoneTimeModel() } label: {
                    JIChevronRow(title: "Time in zone", value: "W · M · 6M", systemImage: "chart.bar.fill")
                        .padding(.horizontal, JISpacing.s4).padding(.vertical, JIChevronRowMetrics.verticalPadding)
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("training-zone-time")
            // B-94 (BP-4): per-lift strength and run / VO₂ max charts, pinned and reordered by the user.
            JISectionHeader("Progress")
            Surface(level: 1, padding: 0) {
                Button { progressCharts = model.makeProgressModel(deps: strengthLogDeps) } label: {
                    JIChevronRow(title: "Progress charts", value: "Strength · Cardio", systemImage: "chart.xyaxis.line")
                        .padding(.horizontal, JISpacing.s4).padding(.vertical, JIChevronRowMetrics.verticalPadding)
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("training-progress")
            // W-GUI TR1 (mockup 04, plan §B): zones are the user's input (W-FIX5: read from their settings).
            JISectionHeader("Zones · your input")
            Surface(level: 1, padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(trainingZoneRows(settings: gateSettings).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { JIRowDivider().padding(.leading, 0) }
                        HStack(alignment: .firstTextBaseline, spacing: JISpacing.s3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).jiFont(.body).foregroundStyle(theme.color(.text))
                                Text(row.subtitle).jiFont(.caption).foregroundStyle(theme.color(.muted))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: JISpacing.s2)
                            Text(row.value).jiFont(.body, weight: .semibold)
                                .foregroundStyle(theme.color(row.value.hasPrefix("—") ? .muted : .text))
                        }
                        .padding(.vertical, JISpacing.s3)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
            }
            .accessibilityIdentifier("training-zones")
        }
    }

    /// B-90 p5: the live model over the on-disk strength log; DEBUG `-muscles-fixture <kind>` swaps in
    /// a fixture and `-muscles-open` pushes the screen (sim screenshots without a tap).
    private func setUpMuscles() {
        if muscles == nil {
            #if DEBUG
            if let kind = musclesLaunchFixture() { muscles = .fixture(kind) }
            #endif
            if muscles == nil, let deps = strengthLogDeps { muscles = .live(store: StrengthSessionLogStore(db: deps.db)) }
        }
        muscles?.reload()
        #if DEBUG
        if CommandLine.arguments.contains("-muscles-open"), muscles != nil { showMuscles = true }
        #endif
    }

    /// PL-6: the selected day as the Planner shows it (its sessions + library workouts).
    private var heroDay: TrainingDayPreview? { model.selectedPlanWeekday.map { model.dayPreview(weekday: $0) } }

    /// "Today" for the device day, else the selected day's date ("Thu 24 Sep").
    private var heroDayLabel: String {
        guard model.selectedDate != model.todayDateString, let date = trainingStripDate(model.selectedDate) else { return "Today" }
        return date.formatted(Date.FormatStyle(timeZone: trainingStripCalendar.timeZone).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// W-B38-B: changes when today's training (session or its exercises / next weights) changes.
    private var watchPlanKey: String {
        guard model.selectedDate == model.todayDateString, let s = model.plannedSessionForSelectedDay else { return "none" }
        return "\(model.todayDateString)|\(s.id)|\(model.exercises.count)|\(progression?.lifts.count ?? 0)"
    }

    /// W-B38-B: the Watch's plan = the logger's prefill for today (A-10 `strengthLogLifts`) + last sets.
    private func sendTodayPlanToWatch() {
        guard let sendWatchPlan, model.selectedDate == model.todayDateString, let session = model.plannedSessionForSelectedDay else { return }
        let lifts = strengthLogLifts(exercises: model.exercises, session: session, progressions: progression?.lifts ?? [])
        guard !lifts.isEmpty else { return }
        let today = model.todayDateString
        let store = strengthLogDeps.map { StrengthSessionLogStore(db: $0.db) }
        var last: [String: [StrengthSetLog]] = [:]
        for lift in lifts { last[lift.exerciseKey] = (try? store?.lastSets(exerciseKey: lift.exerciseKey, before: today)) ?? nil }
        sendWatchPlan(StrengthWatchPlanBuilder.plan(date: today, planSessionId: session.id, title: session.name, lifts: lifts,
                                                    lastSets: last, settings: gateSettings, restS: 90))
    }

    /// W-B38-A A-10: the logger over the selected training (its exercises + progression's next
    /// weight), built once per tap so its state survives re-renders.
    private func openStrengthLog() {
        guard let deps = strengthLogDeps else { return }
        let session = model.plannedSessionForSelectedDay
        let lifts = strengthLogLifts(exercises: model.exercises, session: session, progressions: progression?.lifts ?? [])
        let store = StrengthSessionLogStore(db: deps.db)
        let today = model.todayDateString
        strengthLog = StrengthLogViewModel(lifts: lifts, sessionId: session?.id, sessionName: session?.name, store: store,
                                           outbox: Outbox(db: deps.db), provider: deps.provider, prefs: deps.prefs,
                                           today: { today }, restAlert: .live, reminders: deps.reminders)
        // B-43 P1 rest-end alert permission; RG-76: a denial is kept as the logger's 'Notifications off' state.
        if let log = strengthLog { Task { await log.requestRestAlertPermission() } }
        strengthHistory = StrengthHistoryViewModel(store: store, provider: deps.provider, today: { today })
        showStrengthLog = true
    }

    private var sendToWatchAction: (() -> Void)? {
        #if canImport(WorkoutKit)
        // PL-6: the day's library workout is preselected (the user can still change the pick).
        guard let sendToWatch else { return nil }
        return {
            if let id = trainingHeroTemplateId(day: heroDay) { sendToWatch.pickOnly(id) }
            showSendToWatch = true
        }
        #else
        nil
        #endif
    }
}

/// W-FIX10 F10-2: DEBUG launch routes for the screenshot proofs (developer mode off, no taps).
/// `-send-to-watch-open` alone = the sheet as the hero opens it; `-send-to-watch-open t<id>` =
/// that library workout picked (the library row's action).
nonisolated enum TrainingLaunchSendToWatch: Equatable, Sendable { case hero, template(Int) }

nonisolated func trainingLaunchSendToWatch(_ arguments: [String] = CommandLine.arguments) -> TrainingLaunchSendToWatch? {
    guard let i = arguments.firstIndex(of: "-send-to-watch-open") else { return nil }
    if i + 1 < arguments.count, arguments[i + 1].hasPrefix("t"), let id = Int(arguments[i + 1].dropFirst()) { return .template(id) }
    return .hero
}

/// `-training-day-sheet off` keeps the `-training-day` sheet closed (default: it opens).
nonisolated func trainingLaunchDaySheetOpens(_ arguments: [String] = CommandLine.arguments) -> Bool {
    guard let i = arguments.firstIndex(of: "-training-day-sheet"), i + 1 < arguments.count else { return true }
    return arguments[i + 1] != "off"
}

/// B-90 p5 DEBUG routes: `-muscles-fixture populated|calibrating|empty`, `-muscles-detail <muscle raw>`.
nonisolated func musclesLaunchFixture(_ arguments: [String] = CommandLine.arguments) -> MusclesFixture.Kind? {
    guard let i = arguments.firstIndex(of: "-muscles-fixture"), i + 1 < arguments.count else { return nil }
    return MusclesFixture.Kind(rawValue: arguments[i + 1])
}

nonisolated func musclesLaunchDetail(_ arguments: [String] = CommandLine.arguments) -> Muscle? {
    #if DEBUG
    guard let i = arguments.firstIndex(of: "-muscles-detail"), i + 1 < arguments.count else { return nil }
    return Muscle(rawValue: arguments[i + 1])
    #else
    return nil
    #endif
}

import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub
import JIPersistence
import JIVault
import JIWorkouts
import UserNotifications

// B-33 §2b.4/§5 + close-out (Toby 2026-09-22 "all in one line"): the bar is five content tabs +
// the iOS 27 search role, and the search-role Tab HOSTS the whole Journal (the entries list with
// the system search field + tag scopes on top). `journal` stays in the vocabulary (and in
// `tabContent`) but is no longer one of the five — Energy is.
enum RootTab: Hashable, Identifiable, CaseIterable {
    case today, journal, recovery, energy, nutrition, training, search, more

    var id: Self { self }

    /// B-46 device feedback 1 (Toby 2026-09-22): iOS 27 gives the bar five slots INCLUDING the
    /// search role, so five content tabs + search folded Nutrition/Energy into a system "More"
    /// the app did not control (reproduced on the iPhone 17 Pro sim, `repro-01-today.png`).
    /// The bar is now four explicit icons — Today · Recovery · Training · More — plus the
    /// search-role Tab that hosts the Journal; `More` is ours (Nutrition, Energy).
    static let firstLevel: [RootTab] = leadingTabs + trailingTabs
    /// W-FIX6 F6-18 (Toby 2026-09-28): Search (the Journal entry point) sits BEFORE More —
    /// Today · Recovery · Training · Search · More. The bar is drawn leading tabs, the search-role
    /// Tab, then the trailing tabs, in this order.
    static let leadingTabs: [RootTab] = [.today, .recovery, .training]
    static let trailingTabs: [RootTab] = [.more]
    static let barOrder: [RootTab] = leadingTabs + [.search] + trailingTabs

    var title: String {
        switch self {
        case .today: "Today"; case .journal: "Journal"; case .recovery: "Recovery"
        case .energy: "Energy"; case .nutrition: "Nutrition"; case .training: "Training"
        case .search: "Search"; case .more: "More"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"; case .journal: "book.closed"; case .recovery: "heart"
        case .energy: "flame"; case .nutrition: "fork.knife"; case .training: "dumbbell"
        case .search: "magnifyingglass"; case .more: "ellipsis"
        }
    }

    /// `tab.today`, `tab.search`, … — the identifiers the UI smoke and AppTests use.
    var accessibilityIdentifier: String { "tab.\(String(describing: self))" }
}

struct RootTabView: View {
    /// B-57 W1 (v11 change 1): More = Track / Practice / App.
    static let moreSections: [(header: String, rows: [String])] = [
        ("Track", ["Nutrition", "Energy", "My KPIs", "Goals"]),
        ("Practice", ["Mind"]),
        ("App", ["Settings"]),
    ]

    /// B-57 W1 board: the My KPIs row's trailing value.
    static func moreKpiText(count: Int) -> String { "\(count) chosen" }

    /// W-FIX2 BUG-47 (board 4/04): the App card is one Settings row reading "Hub synced 07:41 ›".
    /// W-FIX4 PF-04: the time is the one sync-pill rule (`TodayViewModel.syncedAt` — the newer of
    /// the hub's last sync and the last HealthKit upload 2xx), never the moment Today fetched.
    static func moreSettingsText(syncedAt: Date?, calendar: Calendar = .current) -> String {
        guard let syncedAt else { return "Not synced yet" }
        let c = calendar.dateComponents([.hour, .minute], from: syncedAt)
        return String(format: "Hub synced %02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// W-FIX4 PF-04: the instant More's Settings row names — Today's sync rule, not its fetch time.
    @MainActor static func moreSettingsDate(_ today: TodayViewModel?) -> Date? { today?.syncedAt }

    /// W-FIX4 fixer PF-04: what every tab stack injects as `jiSyncedAt` — Today's one rule.
    @MainActor static func tabSyncedAt(_ today: TodayViewModel?) -> Date? { today?.syncedAt }

    /// W-FIX6 F6-11 (S1): the ONE source of the morning call (and of what it is made of — the
    /// rationale, the override write, the gate's recovery inputs) is the hub, whichever data source
    /// the tiles read. The debug on-device (T2) source has no verdict; reading the call from it left
    /// Decide, the widget and the Live Activity on a four-day-old cached call (2026-09-28).
    static func verdictSource(hub: (any HealthDataProvider)?, dataSource: any HealthDataProvider) -> any HealthDataProvider {
        hub ?? dataSource
    }

    /// W-FIX6 fixer F6-12/F6-12b: the hub-only screens (Goals, My KPIs, KPI detail, Nutrition,
    /// Energy, Training, gate settings, templates) are built from THIS connection's hub provider,
    /// whichever data source the tiles read. The on-device (T2) source conforms to none of their
    /// protocols, so casting it left Settings' Goals / My KPIs rows dead and More on "Loading…" /
    /// "No data" while the Hub row said Connected.
    static func hubScreensSource(hub: (any HealthDataProvider)?, dataSource: any HealthDataProvider) -> any HealthDataProvider {
        hub ?? dataSource
    }

    /// The provider the hub-only screens read (nil = no connection yet).
    private var hubScreens: (any HealthDataProvider)? {
        env.providerStore.map { Self.hubScreensSource(hub: env.hubProvider, dataSource: $0.provider) }
    }

    /// W-FIX4 fixer PF-04: the shell loads Today's model at launch only when it has no live result
    /// and is not already loading (Today's own `.task` may have started it first).
    @MainActor static func shouldPrimeShellSync(_ today: TodayViewModel?) -> Bool {
        guard let today else { return false }
        return !today.hasLiveResult && today.phase != .loading
    }

    /// W-FIX4 BUG-30: the forced gate is Decide — no "Today" page title and no date subtitle above
    /// its card (the card's date line is the heading), the same as Decide inside `TodayView`.
    static func gateNavigationTitle(pageName: String) -> String { todayNavigationTitle(state: .decide, pageName: pageName) }
    static let gateShowsDateSubtitle = todayNavigationSubtitleShown(state: .decide)

    /// The same count `KpiListView` and Settings show (`KpiSelection.prefKey`).
    private var moreKpiCount: Int {
        let raw = try? env.prefs.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self)
        return KpiSelection.visibleOrder(KpiSelection.reconcile(raw)).count
    }

    @Bindable var env: AppEnvironment
    /// Owned by `JournalInsightApp` (see its doc comment) so a cold-start `.onOpenURL` — which can
    /// fire before this view exists — still has somewhere to land; consumed and cleared here.
    @Binding var pendingDeepLink: DeepLink?
    @State private var showConnection = false
    /// B-57 W4: first-launch onboarding (before the connection sheet), the user's gate settings
    /// (optional cap, zones, Avoid Zone 5) for SessionCoach / Training / the Watch builder.
    @State private var showOnboarding = false
    @State private var onboardingModel: OnboardingViewModel?
    @State private var gateSettings = GateSettings()
    // W5a-L0 (P-settings): the gear opens the real Settings screen (section registry, JIFeatures
    // `SettingsView`); `showConnection`/`ConnectionSheet` stay as the pre-connection sheet the
    // Today error card and `connectionPrompt` present. The model is built async (vault unlock
    // for the Backup row) the moment the sheet opens and dropped on dismiss so a saved hub
    // config or a changed KPI selection is re-read next time.
    @State private var showSettings = false
    /// B-46 item 10: "My KPIs" is presented, never pushed — see the toolbar button's comment.
    @State private var showKpiList = false
    /// W-FIX2 BUG-21: the My KPIs sheet's own stack — a square pushes its detail inside the sheet.
    @State private var kpiSheetPath: [RootRoute] = []
    /// W-FIX2 DEV-04: Decide is showing on Today because the day's gate is not answered yet, or
    /// because `ji://gate` / `-JIForceGate YES` forced it (never clears the stored call).
    @State private var gateOpen = false
    @State private var gateForceConsumed = false
    @State private var goalsSetupModel: GoalsSetupViewModel?
    /// W-TGT L3: the ONE targets document (Goals · Limits · Rules) — imported once at launch
    /// (spec §5), injected outermost as `\.targets` + `\.targetsModel`, edited in Settings › Targets,
    /// KPI detail and Goals, mirrored as one body (`PUT /planning/targets`).
    @State private var targetsModel: TargetsModel?
    /// W-FIX5 fixer (Goals-stale): the goals a GoalsSetup save returned this session (More, Settings or
    /// KpiDetail), shown until the energy model reloads the same document.
    @State private var savedGoals: Goals?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    #if DEBUG
    @State private var showDataQuality = false
    #endif
    @State private var settingsModel: SettingsViewModel?
    @State private var todayModel: TodayViewModel?
    // W5b-L2 close-out wiring: the gate-rationale screen's model, built once alongside `todayModel`
    // and routed through the environment (`GateRationaleView` reads `\.gateRationaleModel`; nil = inert).
    @State private var gateRationaleModel: GateRationaleViewModel?
    // W-GUI T1: Decide's "How the morning call works" row → GateConfig (same model Settings builds).
    @State private var gateConfigModel: GateConfigViewModel?
    // W-B57b (B-62): Decide's verdict-override write model, built beside `gateRationaleModel`.
    @State private var verdictOverrideModel: VerdictOverrideViewModel?
    // B-37 (P-workouts): Training's "Send to Watch" sheet model; provider-scoped like the tab models.
    @State private var sendToWatchModel: SendToWatchViewModel?
    @State private var recoveryModel: RecoveryViewModel?
    /// B-57 W3: one recovery insight per provider (the gate's inputs → the on-device score and the
    /// Apple-night normals); reset with the provider revision, like `todayModel`.
    @State private var recoveryInsight: RecoveryInsightService?
    /// B-57 W5 (A7): the progression rule over the plan + last logged sessions — Day NEXT, Decide
    /// and GoalsSetup "Auto" read it from the environment. Provider-scoped (dropped on a hub switch).
    @State private var progression: ProgressionService?
    // W3a L1–L3 (parallel lanes, PARITY P-energy/P-nutrition/P-training): the view/view-model
    // names below are the ones the wave card gives those lanes; this lane (L4) only wires the
    // tab shell around them and never edits their owned files.
    @State private var energyModel: EnergyViewModel?
    @State private var nutritionModel: NutritionViewModel?
    @State private var trainingModel: TrainingViewModel?
    // W4-L1 (P-journal): on-device only, no hub. `journalDB`/`journalVault` are built once, lazily,
    // the first time the Journal tab is opened (never blocks app launch on a Keychain hit); the DB
    // opens the same backed-up `journalinsight.sqlite` file `env.prefs` already uses (AppDatabase.
    // onDisk()'s default name) — GRDB's `DatabasePool` supports multiple pool instances against one
    // file, same as `prefs`/`cache` already being separate pools today.
    @State private var journalDB: AppDatabase?
    @State private var journalVault: VaultManager?
    // B-57 W1 T27: More → Mind. Built after the vault unlocks (Export does the same), so
    // encrypted check-in / event / WHO-5 rows decode.
    @State private var moreMindModel: MindViewModel?
    @State private var moreMindUnavailable = false
    @State private var journalModel: JournalViewModel?
    @State private var selectedTab: RootTab = .today
    /// B-55: one push path PER TAB (see `TabRouter`) — there is no root `NavigationStack`.
    @State private var router = TabRouter()
    // W7-L3 (P-healthkit-t2-provider): every model above that was built from `store.provider`
    // captured that provider at init, so flipping the debug data-source toggle (Settings → Data
    // source) swapped `ProviderStore.provider` while Today/Recovery/Energy/Nutrition/Training
    // kept querying the old source. `ProviderSwitch.revision` ticks once per effective provider
    // change — the toggle AND a hub reconnect — and this is the single site that invalidates the
    // cache; each tab's `.task` then rebuilds its model against the provider now in the store.
    @State private var providerRevision = 0
    @Environment(\.jiTheme) private var theme

    /// B-46 (L1) dev affordance: `-start-tab <today|recovery|training|nutrition|energy|search|more>`
    /// and `-push-route kpiList` let a scripted simulator run land on any screen without a tap, so
    /// the device defects can be reproduced and screenshotted against the live hub. DEBUG only.
    static func launchArgumentTab(_ arguments: [String] = CommandLine.arguments) -> RootTab? {
        guard let i = arguments.firstIndex(of: "-start-tab"), arguments.index(after: i) < arguments.endIndex else { return nil }
        return RootTab.allCases.first { String(describing: $0) == arguments[arguments.index(after: i)] }
    }

    enum FirstSheet: Equatable { case onboarding, connection }

    /// B-57 W4: today's daytime HRV from the morning's gate signals (`hrv_day`, context only).
    /// nil = no reading; KpiDetail then says "— No data", never a zero.
    static func daytimeHrv(_ today: TodayViewModel?) -> Double? {
        today?.morning?.gateSignals?.first { $0.key == "hrv_day" }?.value
    }

    /// B-57 W4 (Review Focus 4). Fresh install: onboarding first (local only), then the connection
    /// sheet on its dismiss — never both at once. `-no-onboarding` (any build) keeps scripted
    /// simulator runs and sweeps unblocked.
    static func firstSheet(needsOnboarding: Bool, needsConnection: Bool, arguments: [String] = CommandLine.arguments) -> FirstSheet? {
        if needsOnboarding && !arguments.contains("-no-onboarding") { return .onboarding }
        return needsConnection ? .connection : nil
    }

    static func launchArgumentRoute(_ arguments: [String] = CommandLine.arguments) -> RootRoute? {
        guard let i = arguments.firstIndex(of: "-push-route"), arguments.index(after: i) < arguments.endIndex else { return nil }
        return arguments[arguments.index(after: i)] == "kpiList" ? RootRoute.kpiList : nil
    }

    static func launchArgumentPresentsDataQuality(_ arguments: [String] = CommandLine.arguments) -> Bool {
        guard let i = arguments.firstIndex(of: "-push-route"), arguments.index(after: i) < arguments.endIndex else { return false }
        return arguments[arguments.index(after: i)] == "dataQuality"
    }

    var body: some View {
        // B-55: NO root `NavigationStack` around the shell. It used to wrap this whole ZStack with
        // a bound path while the search-role Tab and More ran their own stacks nested under it —
        // once Search had been mounted, any root path change (a KPI push or its pop) trapped in
        // `NavigationColumnState.boundPathChange` (`AnyNavigationPath.Error.comparisonTypeMismatch`),
        // and push-then-tab-switch looped the nested navigation controllers' inset layout (the
        // device hang-kill). Each tab now owns its stack (`tabStack`), side by side, never nested.
        // W2a TabTransition fix for the W1 hard cut (CONTEXT-IOS-FOUNDATION.md §Step 4): a
        // native `TabView` can only ever have ONE Tab's own content mounted at a time, so
        // content living strictly *inside* a `Tab`'s body can never crossfade with a sibling
        // Tab's content — there is no frame where both exist to interpolate between. The real
        // screens instead live in this `TabTransition` layer, drawn *behind* the TabView in the
        // ZStack; the TabView on top keeps design decision #7's native tab bar chrome (visible,
        // tappable, safe-area-correct) while its own per-tab content is `Color.clear` with hit
        // testing disabled, so every tap/scroll/pull-to-refresh above the bar passes straight
        // through to the real, crossfading content behind it.
        ZStack {
            TabTransition(selection: selectedTab, content: tabContent)
            TabView(selection: $selectedTab) {
                ForEach(RootTab.leadingTabs) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab) {
                        transparentTabContent
                    }
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                    .accessibilityLabel(tab.title)
                }
                // B-46 device feedback 11: the Journal + `.searchable` live INSIDE the real
                // search-role Tab's content (not the pass-through `TabTransition` layer), so
                // iOS 27 binds the field to this Tab and the bar morphs into it on selection.
                // The pass-through layer renders nothing for `.search` (see `tabContent`).
                // W-FIX6 fixer F6-18: a plain Tab, not `role: .search` — iOS 27 pins the search-role
                // Tab to the trailing edge whatever the declaration order, so "Search before More"
                // is only possible without the role. `.searchable` inside still shows the field.
                Tab(RootTab.search.title, systemImage: RootTab.search.symbol, value: RootTab.search) {
                    searchTab
                }
                .accessibilityIdentifier(RootTab.search.accessibilityIdentifier)
                // W-FIX6 F6-18: More after Search.
                ForEach(RootTab.trailingTabs) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab) {
                        transparentTabContent
                    }
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                    .accessibilityLabel(tab.title)
                }
            }
            .tabViewStyle(.sidebarAdaptable)   // §8.2: tab bar on iPhone, sidebar on iPad — zero code per tab
        }
        .jiPageGround()   // W-GUI F3: the tinted ground (report §4.1), never a flat bg
        // B-33 §8.0: the whole shell renders in the native language. §5: tab/selection tint is
        // the personalization accent — W-FIX3 C-c: inherited from the app root's
        // `.tint(theme.accent)` (the user's Appearance choice); a hard-coded default-accent tint
        // here used to override it back to the default for every tab and sheet.
        .jiTheme(.native)
        .onAppear { env.makeEnergyBand() }
        .onChange(of: ProviderSwitch.shared.revision) { _, revision in
            guard revision != providerRevision else { return }
            providerRevision = revision
            invalidateProviderScopedModels()
        }
        .onAppear {
            // B-57 W4 (Toby 2026-09-24): Toby's pre-W4 install keeps its cap, Avoid Zone 5 and
            // zones; a fresh install gets nothing. Runs once, BEFORE onboarding reads the store.
            let store = GateSettingsStore(prefs: env.prefs)
            let migrated = store.migratePreW4InstallIfNeeded()
            // W-TGT L3 (spec §5, L1 hand-off): the one-shot targets import, BEFORE anything reads
            // targets — verbatim, missing = nil, the sleep goal never seeded — then its first
            // mirror (queued by the import) is sent. The pre-W4 push above still goes first.
            startTargets()
            gateSettings = store.load()
            if migrated {
                // The hub's missing-file default is the same values, so a failed push changes nothing.
                let mirror = gateSettingsMirror()
                Task { await mirror.save(store.load()) }
            }
            switch Self.firstSheet(needsOnboarding: OnboardingGate.needsOnboarding(env.prefs), needsConnection: env.needsConnection) {
            case .onboarding?:
                // W-FIX5 W4-2: the real night count (the cover also reads the live insight below).
                if recoveryInsight == nil, let store = env.providerStore {
                    recoveryInsight = RecoveryInsightService(provider: Self.verdictSource(hub: env.hubProvider, dataSource: store.provider) as? any RecoveryInputsProviding, cache: env.cache)
                    env.recoveryInsight = recoveryInsight
                }
                onboardingModel = OnboardingViewModel(prefs: env.prefs, mirror: gateSettingsMirror(),
                                                      reminderCenter: UNUserNotificationCenter.current(),
                                                      nightsSoFar: .init(recovery: recoveryInsight?.result))
                showOnboarding = true
            case .connection?: showConnection = true
            case nil: break
            }
        }
        .onboardingCover(isPresented: $showOnboarding) {
            if let onboardingModel {
                OnboardingFlowView(model: onboardingModel) { showOnboarding = false }
                    .environment(\.recoveryInsight, recoveryInsight)
                    .task { await recoveryInsight?.refreshIfStale() }
            }
        }
        .onChange(of: showOnboarding) { _, shown in
            guard !shown else { return }
            onboardingModel = nil
            reloadGateSettings()
            targetsModel?.reload()   // W-TGT: onboarding wrote its cap / zones / preset into the document
            if env.needsConnection { showConnection = true }
        }
        .onChange(of: gateSettings) { _, _ in
            rebuildSendToWatchModel()
            // B-57 W5: the widget/Watch/Live Activity cap follows the user's setting (or its removal) now.
            env.republishSnapshot()
        }
        // W-FIX4 fixer PF-04: the hub's last sync is known whichever tab opens first (a launch
        // onto Recovery never mounts Day, which is what used to build and load Today's model).
        .task(id: providerRevision) { await primeShellSync() }
        // W-FIX6 F6-11: a new override (Go / Adjust) reaches the widget and Live Activity at once.
        .onChange(of: verdictOverrideModel?.current) { _, _ in env.republishSnapshot() }
        // W-FIX6 F6-2: the glance normals follow the recovery insight whenever it (re)loads.
        .onChange(of: recoveryInsight?.fetchedAt) { _, _ in env.republishSnapshot() }
        #if DEBUG
        .onAppear {
            if let tab = Self.launchArgumentTab() { selectedTab = tab }
            if Self.launchArgumentRoute() == .kpiList {
                Task { try? await Task.sleep(for: .seconds(3)); showKpiList = true }
            }
            if Self.launchArgumentPresentsDataQuality() {
                Task { try? await Task.sleep(for: .seconds(3)); showDataQuality = true }
            }
        }
        #endif
        .onAppear { if let link = pendingDeepLink { handle(link); pendingDeepLink = nil } }
        .onChange(of: pendingDeepLink) { _, link in
            guard let link else { return }
            handle(link)
            pendingDeepLink = nil
        }
        // W-FIX2 DEV-04: the first launch (or return) after local midnight opens Decide.
        .onAppear { evaluateGate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                evaluateGate()
                if let targetsModel { Task { await targetsModel.pushIfPending() } }   // W-TGT: queued body
                goalsSetupModel?.refreshHubPending()   // W-FIX5 DEV-15
            }
        }
        .onChange(of: todayModel?.morningState) { old, new in
            // Decide answered inline (a new verdict date mid-day) counts as today's answer too.
            if old == .decide, let new, new != .decide { recordGateAnswered() }
        }
        #if DEBUG
        .sheet(isPresented: $showDataQuality) {
            NavigationStack {
                if let model = DataQualityAccess.shared.makeViewModel(cache: env.cache) { DataQualityView(model: model) } else { DataQualityUnavailableView() }
            }
        }
        #endif
        .sheet(isPresented: $showKpiList, onDismiss: { kpiSheetPath = [] }) {
            // W-FIX2 BUG-21: squares open their detail inside the sheet; Done closes it (board 2/02, 2/04).
            // W-B57-W3 fixer PF-04: the sheet's stack gets the tab stacks' environment (sync instant,
            // recovery insight), so KpiDetail from My KPIs names the same time as the tab path.
            shellStackEnvironment(NavigationStack(path: $kpiSheetPath) {
                kpiListDestination(onSelectKpi: { metric in
                    let route = RootRoute.kpiDetail(metric: metric)
                    if kpiSheetPath.last != route { kpiSheetPath.append(route) }
                })
                .navigationTitle("My KPIs")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        // W-GUI R4 (mockup 23): Done is a checkmark (BUG-21: it stays; squares push their detail).
                        // W-FIX8 G-1: a toolbar button — the bar draws the one glass (a JIGlassButton here sat crammed under the sheet corner).
                        JIToolbarButton("checkmark", label: "Done") { showKpiList = false }.accessibilityIdentifier("kpis.done")
                    }
                }
                .navigationDestination(for: RootRoute.self) { route in
                    switch route {
                    case .kpiDetail(let metric): kpiDetailDestination(metric: metric)
                    case .kpiList: kpiListDestination(onSelectKpi: nil)
                    case .trends: trendsDestination(onSelectKpi: { metric in
                        let route = RootRoute.kpiDetail(metric: metric)
                        if kpiSheetPath.last != route { kpiSheetPath.append(route) }
                    })
                    }
                }
            })
        }
        .sheet(isPresented: $showSettings, onDismiss: { settingsModel = nil; reloadGateSettings() }) {
            if let settingsModel {
                // W-FIX5 fixer: Settings → My KPIs / Gate thresholds read the same recovery insight
                // (Load square, onboarding nights) as the tab stacks — a sheet does not inherit it.
                shellStackEnvironment(SettingsView(model: settingsModel))
            } else {
                ProgressView().task { settingsModel = await makeSettingsModel() }
            }
        }
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(
                store: ConnectionConfigStore(secrets: env.secrets),
                backloadModel: HealthBackloadViewModel(runner: env.backload, hrvPrefs: env.hrvPrefs),   // W2h/W2i: Garmin → Apple Health
                healthPermissionModel: env.makeHealthPermissionModel()                                  // W2d: Apple Watch → hub (dso 4)
            ) { config in
                env.apply(config)
                invalidateProviderScopedModels()
            }
        }
        // B-57 W2 (B-73): every nutrition surface (Nutrition, KpiList, KpiDetail, Trends, the
        // WeeklyPlan row) draws its goal tick / caption from the user's own goals, via this one
        // injection. `.unknown` only until the band service exists (built on appear above).
        // fixer2 C3-KPI-GOALS: OUTERMOST, after every `.sheet` — a sheet reads the environment
        // where its modifier sits, so the My KPIs / Settings sheets missed it when it came first.
        .environment(\.nutritionGoals, env.energyBand?.snapshot ?? .unknown)
        // W-TGT L3: the targets document and its editor, outermost for the same reason.
        .environment(\.targets, targetsModel?.document)
        .environment(\.targetsModel, targetsModel)
        // B-57 W4: the user's gate settings, outermost too (Training → SessionCoach reads them).
        .environment(\.gateSettings, gateSettings)
        // B-57 W5 (A7): progression + this week for Day, Decide, Goals and GoalsSetup — outermost,
        // after every `.sheet`, for the same reason as nutritionGoals above.
        .environment(\.progression, progression)
        .environment(\.trainingWeekSummary, weekSummary)
        // A weekday assignment (or a new done session) moves the widgets' plan ring and next session now.
        .onChange(of: weekSummary) { _, _ in env.republishSnapshot() }
        .onChange(of: trainingModel.map(ObjectIdentifier.init)) { _, _ in installGlancePlan() }
    }

    /// B-57 W5 (A7): the live Training model's week when the tab exists, else the cached plan (B-52 keys).
    private var weekSummary: TrainingWeekSummary? {
        trainingModel?.weekSummary
            ?? TrainingViewModel.cachedWeekSummary(cache: env.cache, today: AppEnvironment.isoDay(Date()))
    }

    /// B-57 W5 (A7): hands the live week to the glances (nil model → AppEnvironment reads the cached
    /// plan itself). Weak: the closure outlives neither a hub switch nor the Training model.
    private func installGlancePlan() {
        let model = trainingModel
        env.glancePlan = { [weak model] in model.flatMap { GlancePlan($0.weekSummary) } }
    }

    /// B-57 W4: the hub mirror for gate settings over the current provider (nil = local only).
    private func gateSettingsMirror() -> GateSettingsMirror {
        GateSettingsMirror(prefs: env.prefs, provider: hubScreens as? any GateSettingsProviding)
    }

    /// Re-reads the stored settings (after onboarding, or a change in Targets › Limits).
    private func reloadGateSettings() {
        let latest = GateSettingsStore(prefs: env.prefs).load()
        if latest != gateSettings { gateSettings = latest }
    }

    // MARK: - W-TGT L3: the targets document

    /// Launch (spec §5): import once over the app's own caches (`kpi.targets` lives in `env.cache`,
    /// so a rule changed on the hub is carried over, never reset), build the model, send the
    /// queued first body.
    private func startTargets() {
        let outbox = try? Outbox(db: .onDisk())
        TargetsModel.migrateAtLaunch(prefs: env.prefs, cache: env.cache,
                                     goals: (try? AppDatabase.onDisk()).map { GoalStore(db: $0) }, outbox: outbox,
                                     log: { print("[targets] \($0)") })
        let model = makeTargetsModel(outbox: outbox)
        targetsModel = model
        reloadGateSettings()
        Task { await model.pushIfPending() }
    }

    /// The model over THIS connection's hub (rebuilt on a hub switch, like the tab models).
    private func makeTargetsModel(outbox: Outbox?) -> TargetsModel {
        let mirror = outbox.map { outbox in
            TargetsMirror(prefs: env.prefs, outbox: outbox, drainer: hubScreens.map { OutboxDrainer(outbox: outbox, hub: $0) })
        }
        let cache = env.cache
        return TargetsModel(prefs: env.prefs, mirror: mirror, makeLimitsModel: { makeLimitsModel() },
                            normal: { KpiDetailViewModel.cachedTargetNormal($0, cache: cache) }) { _ in
            // A goal / limit / rule changed: Today Fuel, KPI captions, Goals (the band reads the same
            // document), the Watch limits and the glances follow at once.
            reloadGateSettings()
            Task { await env.refreshEnergyBand() }
            env.republishSnapshot()
        }
    }

    /// The Limits engine (cap + 8-week re-check, zones, Avoid Zone 5) — Targets and Decide's
    /// "How the morning call works" share it.
    private func makeLimitsModel() -> GateConfigViewModel {
        if let gateConfigModel { return gateConfigModel }
        let model = GateConfigViewModel(prefStore: env.prefs, mirror: gateSettingsMirror(),
                                        reminderCenter: UNUserNotificationCenter.current())
        gateConfigModel = model
        return model
    }

    /// The Watch builder takes the user's own limits (no cap and no Zone 5 avoidance ⇒ `.none`,
    /// so no limit is applied). Built with the Training tab; rebuilt when the settings change.
    private func makeSendToWatchModel() -> SendToWatchViewModel? {
        guard let templates = hubScreens as? any WorkoutTemplatesProviding else { return nil }
        let sender: any WorkoutSending = CommandLine.arguments.contains("-ui-testing") ? FakeWorkoutSender() : WorkoutSchedulerSender()
        let limits = gateSettings.workoutLimits
        return SendToWatchViewModel(provider: templates, sender: sender,
                                    builder: { try WorkoutBuilder.build($0, limits: limits) },
                                    openSettings: {
                                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                    },
                                    limits: limits)
    }

    private func rebuildSendToWatchModel() {
        guard sendToWatchModel != nil else { return }
        sendToWatchModel = makeSendToWatchModel()
    }

    /// Drops every view model that captured `ProviderStore.provider` at init. Deliberately does
    /// NOT drop `settingsModel`: the data-source toggle lives inside that sheet, so rebuilding it
    /// mid-flip would tear down the row the user just tapped.
    private func invalidateProviderScopedModels() {
        // W-TGT: the mirror sends through THIS connection's hub.
        if targetsModel != nil { targetsModel = makeTargetsModel(outbox: try? Outbox(db: .onDisk())) }
        gateConfigModel = nil
        // Settings owns the HealthBackloadViewModel whose backloader was built on the PREVIOUS
        // HubClient — without this reset a backload after a hub-URL change still hits the old host
        // (device 2026-09-20: "network error" against a working hub).
        settingsModel = nil
        todayModel = nil
        recoveryModel = nil
        recoveryInsight = nil
        progression = nil
        energyModel = nil
        nutritionModel = nil
        trainingModel = nil
        sendToWatchModel = nil
    }

    /// Per-tab placeholder for the chrome-only `TabView`. `Color.clear.allowsHitTesting(false)`
    /// alone is NOT enough on iOS 27: the native `TabView` is a `UITabBarController` whose UIKit
    /// views (a) paint an opaque `systemBackground`, which covered the whole `TabTransition` layer
    /// with solid black, and (b) return themselves from `hitTest`, which swallowed every tap and
    /// scroll before it could reach the content behind. Both were found in the W2b close-out
    /// simulator smoke (empty screens, dead tiles). `TabHostPassThrough` fixes both from inside the
    /// tab's UIKit hierarchy — see its doc comment.
    private var transparentTabContent: some View {
        Color.clear
            .background(TabHostPassThrough())
            .allowsHitTesting(false)
    }

    /// B-55: the pass-through layer's content — every content tab inside its own stack.
    @ViewBuilder
    private func tabContent(_ tab: RootTab) -> some View {
        switch tab {
        // B-46 item 11: the search Tab owns its own content (and stack) — nothing behind it.
        case .search: Color.clear
        default: tabStack(tab) { tabRoot(tab) }
        }
    }

    /// B-55: one `NavigationStack` per tab, bound to that tab's slice of `router`, carrying the
    /// shell chrome (My KPIs + Settings) and the `RootRoute` destinations. Stacks are siblings —
    /// the only other stacks on screen are the search Tab's and modal sheets', never an ancestor.
    private func tabStack<Content: View>(_ tab: RootTab, @ViewBuilder content: () -> Content) -> some View {
        shellStackEnvironment(NavigationStack(path: Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })) {
            content()
                .toolbar { shellToolbar }
                // B-57 W1: shell hooks Recovery (L3) reads — the catalogue sheet and a KPI push.
                .environment(\.openKpiCatalogue, { showKpiList = true })
                // W-FIX2 BUG-13: a tile's detail pushes on the tab it sits on (Recovery → Recovery).
                .environment(\.openKpiDetail, { metric in pushKpiDetail(metric, on: tab) })
                .navigationDestination(for: RootRoute.self) { route in
                    switch route {
                    case .kpiDetail(let metric): kpiDetailDestination(metric: metric)
                    case .kpiList: kpiListDestination(onSelectKpi: { metric in pushKpiDetail(metric, on: tab) })
                    case .trends: trendsDestination(onSelectKpi: { metric in pushKpiDetail(metric, on: tab) })
                    }
                }
        })
    }

    /// The shell environment every navigation stack gets — each tab stack AND the My KPIs sheet's
    /// stack (a sheet does not inherit a tab stack's environment; W-B57-W3 fixer PF-04).
    private func shellStackEnvironment<V: View>(_ content: V) -> some View {
        content
            // W-FIX4 fixer PF-04: the one sync instant for every screen's `OneSyncedPill` (root and
            // pushed), so Recovery/Training/Energy/Nutrition name the hub time Day and More name.
            .environment(\.jiSyncedAt, Self.tabSyncedAt(todayModel))
            // B-57 W3: the recovery score / normals for every screen of the stack (root and pushed).
            .environment(\.recoveryInsight, recoveryInsight)
    }

    // W2i: the connection sheet used to be reachable only before a hub was configured or from the
    // Today error card — once connected, Settings (incl. the Health backload) had no entry point.
    // Keep it one tap away from every tab.
    @ToolbarContentBuilder
    private var shellToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // B-46 device feedback 10: My KPIs is a modal presentation, never a push (the first
            // trigger of the B-55 trap; the per-tab stacks above removed the shape underneath it).
            Button { showKpiList = true } label: { Image(systemName: "list.bullet.rectangle") }
                .accessibilityLabel("My KPIs")
                .accessibilityIdentifier("root.kpis")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("root.settings")
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: RootTab) -> some View {
        switch tab {
        case .today: todayTab
        case .journal: journalTab
        case .recovery: recoveryTab
        case .energy: energyTab
        case .nutrition: nutritionTab
        case .training: trainingTab
        case .more: moreTab
        case .search: Color.clear
        }
    }

    @ViewBuilder
    private var todayTab: some View {
        if let store = env.providerStore {
            if let todayModel, gateOpen, todayModel.phase == .loaded || !todayModel.hasLiveResult {
                gateScreen(todayModel)
            } else if let todayModel {
                TodayView(
                    model: todayModel,
                    onOpenConnection: { showConnection = true },
                    onSelectKpi: { metric in pushKpiDetail(metric, on: .today) },
                    onOpenTrends: { router.push(.trends, on: .today) },
                    makeGateRespondModel: { recommendation in makeGateRespondModel(recommendation, provider: store.provider) }
                )
                .environment(\.gateRationaleModel, gateRationaleModel)
                .environment(\.verdictOverrideModel, verdictOverrideModel)
            } else {
                ProgressView()
                    .task { makeTodayModels(store: store) }
            }
        } else {
            connectionPrompt
        }
    }

    /// W-FIX4 fixer PF-04: build Today's model if no tab has yet, and load it once, so the shell's
    /// `jiSyncedAt` carries the hub's last sync on every tab.
    private func primeShellSync() async {
        guard let store = env.providerStore else { return }
        makeTodayModels(store: store)
        if let today = todayModel, Self.shouldPrimeShellSync(today) { await today.load() }
        // W-FIX6 F6-2: a launch onto More never mounts Decide/Recovery, which is what loaded the
        // insight — so the first glance went out with "no normal". Load it here and republish.
        await env.refreshGlanceInsight()
    }

    /// Today's model + its siblings (rationale, override). Shared by the Today tab and More (the
    /// Goals row reads the latest weight from Today's gate rows).
    private func makeTodayModels(store: ProviderStore) {
        let verdictSource = Self.verdictSource(hub: env.hubProvider, dataSource: store.provider)
        if recoveryInsight == nil {
            recoveryInsight = RecoveryInsightService(provider: verdictSource as? any RecoveryInputsProviding, cache: env.cache)
        }
        // B-57 W5: the glances read the HRV/RHR normals from the same insight (weak on env).
        env.recoveryInsight = recoveryInsight
        if progression == nil {
            progression = ProgressionService(provider: Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any TrainingProviding, cache: env.cache, prefs: env.prefs)
        }
        installGlancePlan()
        guard todayModel == nil else { return }
        todayModel = TodayViewModel(provider: store.provider, verdictProvider: verdictSource, cache: env.cache, prefs: env.prefs)
        env.bind(today: todayModel, recovery: recoveryModel)
        gateRationaleModel = GateRationaleViewModel(provider: verdictSource)
        // Outbox on the same on-disk database the drainer reads (see makeGateRespondModel).
        if let p = verdictSource as? any VerdictOverrideProviding,
           let db = journalDB ?? { let d = (try? AppDatabase.onDisk()); journalDB = d; return d }() {
            verdictOverrideModel = VerdictOverrideViewModel(provider: p, outbox: Outbox(db: db))
        }
        // W-FIX6 F6-11: the glances show the call as the user made it (Decide's headline).
        env.currentOverride = { [weak model = verdictOverrideModel] in model?.current }
    }

    // W5b-L4 (P-gate-respond) close-out wiring: the gate answer card's model, built by `TodayView`
    // whenever the loaded gate's recommendation changes. Outbox-first over the same on-disk
    // `AppDatabase` the Journal tab uses (v4_decision_log lives there); nil when the hub provider
    // cannot answer gates or the database cannot open — the card then simply does not mount.
    private func makeGateRespondModel(_ recommendation: GateRecommendation, provider: any HealthDataProvider) -> GateRespondViewModel? {
        guard let respondProvider = provider as? any GateRespondProviding else { return nil }
        let db = journalDB ?? { let d = (try? AppDatabase.onDisk()); journalDB = d; return d }()
        guard let db else { return nil }
        return GateRespondViewModel(recommendation: recommendation, provider: respondProvider, outbox: Outbox(db: db), decisionLog: DecisionLogStore(db: db))
    }

    // W4-L1 (P-journal): fully on-device, no `env.providerStore`/hub gate — the Journal tab is
    // reachable even before a hub connection exists, unlike every W3a tab above.
    @ViewBuilder
    private var journalTab: some View {
        if let journalModel {
            JournalView(model: journalModel)
        } else {
            ProgressView()
                .task {
                    let db = journalDB ?? { let d = (try? AppDatabase.onDisk()); journalDB = d; return d }()
                    let vault = journalVault ?? { let v = VaultManager(keychain: SecureKeychainService()); journalVault = v; return v }()
                    guard let db else { return }
                    journalModel = JournalViewModel(db: db, vault: vault)
                }
        }
    }

    /// B-46 device feedback 1: our own "More" — the two tabs that no longer fit the bar. A plain
    /// inset-grouped list, so the screens behind it are the same `nutritionTab`/`energyTab` views.
    @ViewBuilder
    /// B-55: rendered inside More's own `tabStack`, so the links push there.
    private var moreTab: some View {
        // W-GUI M1 (mockup 08): the List became grouped cards on the ground — every row a
        // JIChevronRow (report §7 rule 2), values from MoreRowValues (unchanged), the Apple
        // Health row's "Connected" from the PF-04 upload time, and the mirror caption.
        ScreenScroll {
            VStack(alignment: .leading, spacing: 0) {
                // W-FIX3 BUG-33: at AX sizes the subtitle wraps here instead of being cut in the bar.
                if jiTitleWrapsInList(typeSize) {
                    Text(Self.moreSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, JISpacing.s1)
                        .accessibilityIdentifier("more.subtitle")
                }
                JISectionHeader("Track")
                moreCard {
                    NavigationLink { nutritionTab } label: {
                        JIChevronRow { MoreRowLabel("Nutrition", systemImage: RootTab.nutrition.symbol, value: moreNutritionRow) }
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more.nutrition")
                    JIRowDivider()
                    NavigationLink { energyTab } label: {
                        JIChevronRow { MoreRowLabel("Energy", systemImage: RootTab.energy.symbol, value: moreEnergyRow) }
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more.energy")
                    JIRowDivider()
                    // W-FIX2 BUG-47: still presented (B-46 item 10), but drawn as the same chevron row
                    // as its neighbours — plain title, muted value, disclosure chevron.
                    Button { showKpiList = true } label: {
                        JIChevronRow {
                            MoreRowLabel("My KPIs", systemImage: "chart.bar",
                                         value: MoreRowValue(lead: Self.moreKpiText(count: moreKpiCount), rest: "", style: .muted))
                        }
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more.kpis")
                    JIRowDivider()
                    NavigationLink { moreGoals } label: {
                        JIChevronRow { MoreRowLabel("Goals", systemImage: "target", value: moreGoalsRow) }
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more.goals")
                }
                JISectionHeader("Practice")
                moreCard {
                    NavigationLink { moreMind } label: {
                        JIChevronRow { MoreRowLabel("Mind", systemImage: "water.waves", value: moreMindValue(who5Pct: moreMindModel?.latestWho5?.pct)) }
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more.mind")
                }
                JISectionHeader("App")
                moreCard {
                    Button { showSettings = true } label: {
                        JIChevronRow {
                            MoreRowLabel("Apple Health", systemImage: "heart.text.square",
                                         value: MoreRowValue(lead: moreAppleHealthText(lastUpload: healthKitLastUploadDate(),
                                                                                      readLocally: TodayWorkoutsModel.shared.hasReadHealth || !HealthDailyTotalsFeed.shared.latest.isEmpty), rest: "", style: .muted))
                        }
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more.appleHealth")
                    JIRowDivider()
                    // W-FIX2 BUG-47 (board 4/04): one row, "Hub synced 07:41 ›" — text, not a pill.
                    Button { showSettings = true } label: {
                        JIChevronRow {
                            MoreRowLabel("Settings", systemImage: "slider.horizontal.3",
                                         value: MoreRowValue(lead: Self.moreSettingsText(syncedAt: Self.moreSettingsDate(todayModel)), rest: "", style: .muted))
                        }
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("more.settings")
                }
                Text(moreMirrorCaption).jiFont(.caption).foregroundStyle(theme.color(.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, JISpacing.s4).padding(.top, JISpacing.s4)
                    .accessibilityIdentifier("more.caption")
            }
            .padding(.horizontal, JISpacing.sideMargin).padding(.top, 8).padding(.bottom, 32)
            .readableColumn()
        }
        .jiPageGround()
        .navigationTitle("More")
        .navigationSubtitle(jiTitleWrapsInList(typeSize) ? "" : Self.moreSubtitle)
        .task { await loadMoreSummaries() }
    }

    static let moreSubtitle = "Everything that is not a daily decision"

    /// W-GUI M1: a grouped card of More rows (level-1 surface, 6 / 16 padding, rows carry their own 12).
    private func moreCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Surface(level: 1, padding: 0) {
            VStack(spacing: 0) { content() }
                .padding(.horizontal, JISpacing.s4).padding(.vertical, 6)
        }
    }

    // B-57 W1 r5 (h3): the More rows' trailing values read the same models the screens behind
    // them use (built here when More is opened first); missing data is "—" + a reason.
    private var moreNutritionRow: MoreRowValue {
        let today = String(Date().ISO8601Format().prefix(10))
        let day = nutritionModel?.day.flatMap { $0.date == today ? $0 : nil }
        // W-DATA fixer R1: no food today → the newest logged day of the week, named by its day.
        let latest = moreNutritionLatestIntake(today: today, todayKcal: day?.total.kcal, week: nutritionModel?.week ?? [])
        return Self.moreNutritionRowValue(consumedKcal: latest?.kcal, userGoals: env.energyBand?.goals,
                                          asOf: kpiAsOfLabel(valueDate: latest?.date, today: today))
    }

    /// B-73 (W-B57-W2 fixer MORE-NUTRITION-GOAL): "consumed / goal" against the user's own kcal
    /// target (`goals.macros`) only — never YAZIO's day goal nor the hub document. Unset = consumed alone.
    static func moreNutritionRowValue(consumedKcal: Double?, userGoals: MacroGoals?, asOf: String? = nil) -> MoreRowValue {
        moreNutritionValue(consumedKcal: consumedKcal, goalKcal: userGoals?.targetKcal, asOf: asOf)
    }

    private var moreEnergyRow: MoreRowValue {
        moreEnergyValue(avgDeficit7d: energyModel?.report?.avgDeficitCorrected7d, trackingDays: energyModel?.report?.trackingDays ?? 0)
    }

    /// W-FIX2 BUG-42 (board: "80.2 → 75.0 kg" on More AND Settings): the goal's start weight →
    /// target, from the same hub goals document Settings' row reads (`settingsGoalsTrailing`).
    private var moreGoalsRow: MoreRowValue {
        let doc = targetsModel?.storedDocument
        return Self.moreGoalsRowValue(goalsFromTargets(doc, hub: goalsShown(hub: energyModel?.goals, saved: savedGoals)),
                                      countOtherGoals: doc != nil, otherGoalCount: doc.map(targetsOtherGoalCount))
    }

    /// W-TGT fixer 2 R2: without a weight goal the row counts the other goals the user set ("2 goals
    /// set") — only from the phone's own document (the hub's nutrition block is seeded, not his).
    static func moreGoalsRowValue(_ goals: Goals?, countOtherGoals: Bool = false, otherGoalCount: Int? = nil) -> MoreRowValue {
        moreGoalsValue(currentKg: goals?.weight.baseKg, targetKg: goals?.weight.targetKg,
                       otherGoals: countOtherGoals ? (otherGoalCount ?? goalsSetCount(goals)) : 0)
    }

    /// W-FIX2 BUG-41: the Goals board's inputs, from the models More already loads.
    private var moreGoalsBoard: GoalsBoardInput? {
        guard let energyModel, energyModel.goals != nil || energyModel.hasLiveResult || savedGoals != nil || targetsModel != nil else { return nil }
        let gate = todayModel?.gate
        let yesterday = String(Calendar.current.date(byAdding: .day, value: -1, to: Date())!.ISO8601Format().prefix(10))
        let nutrition = nutritionModel?.week.first { $0.date == yesterday }
        let energyDay = energyModel.report?.days.first { $0.date == yesterday }
        let stepsRow = gate?.daily.first { $0.date == yesterday }
        return GoalsBoardInput(
            goals: goalsFromTargets(targetsModel?.storedDocument, hub: goalsShown(hub: energyModel.goals, saved: savedGoals)),
            latestKg: KpiMetrics.latest(for: .weight, recovery: [], nutrition: [], dailyRows: gate?.daily ?? [], gateAverages: gate?.averages)?.value,
            avgDeficit7d: energyModel.report?.avgDeficitCorrected7d,
            trackingDays: energyModel.report?.trackingDays ?? 0,
            yesterdayKcal: nutrition?.kcalConsumed ?? energyDay?.kcalConsumed,
            yesterdayProteinG: nutrition?.proteinG,
            yesterdaySteps: stepsRow?.values["steps"] ?? nil
        )
    }

    private func loadMoreSummaries() async {
        if let store = env.providerStore {
            makeTodayModels(store: store)
            if energyModel == nil, let p = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any EnergyProviding {
                energyModel = EnergyViewModel(provider: p, cache: env.cache, now: Date.init, band: env.makeEnergyBand())
            }
            if nutritionModel == nil, let p = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any NutritionProviding {
                nutritionModel = NutritionViewModel(provider: p, cache: env.cache, now: Date.init)
            }
            if goalsSetupModel == nil, let p = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any GoalsSetupProviding {
                goalsSetupModel = makeGoalsSetup(p)
            }
        }
        if moreMindModel == nil, !moreMindUnavailable { await makeMoreMindModel() }
        // Loaded side by side (each restores its cache first, then fetches live).
        var loads: [Task<Void, Never>] = []
        if let today = todayModel, !today.hasLiveResult { loads.append(Task { await today.load() }) }
        if let energy = energyModel, !energy.hasLiveResult { loads.append(Task { await energy.load() }) }
        if let nutrition = nutritionModel, !nutrition.hasLiveResult { loads.append(Task { await nutrition.load() }) }
        if let mind = moreMindModel, mind.phase == .idle { loads.append(Task { await mind.load() }) }
        for load in loads { await load.value }
    }

    @ViewBuilder private var moreGoals: some View {
        if let db = journalDB ?? (try? AppDatabase.onDisk()) {
            GoalsView(model: GoalsViewModel(store: GoalStore(db: db)), board: moreGoalsBoard, setupModel: goalsSetupModel)
        } else {
            screenUnavailable(title: "Goals unavailable", systemImage: "target")
        }
    }

    /// The Mind stores take the vault cipher (as Export's do), so the model is built after
    /// `vault.unlock()` — the `makeSettingsModel` pattern — never with the identity cipher.
    @ViewBuilder private var moreMind: some View {
        if let moreMindModel {
            MindView(model: moreMindModel)
        } else if moreMindUnavailable {
            screenUnavailable(title: "Mind unavailable", systemImage: "water.waves")
        } else {
            ProgressView().task { await makeMoreMindModel() }
        }
    }

    private func makeMoreMindModel() async {
        let db = journalDB ?? (try? AppDatabase.onDisk())
        journalDB = db
        let vault = journalVault ?? VaultManager(keychain: SecureKeychainService())
        journalVault = vault
        guard let db, let cipher = try? await vault.unlock() else { moreMindUnavailable = true; return }
        moreMindModel = MindViewModel(
            checkins: CheckInStore(db: db, cipher: cipher),
            eventStore: EventStore(db: db, cipher: cipher),
            who5Store: Who5Store(db: db, cipher: cipher)
        )
    }

    @ViewBuilder
    private var recoveryTab: some View {
        if let store = env.providerStore {
            if let recoveryModel {
                RecoveryView(model: recoveryModel)
            } else {
                ProgressView()
                    .task {
                        recoveryModel = RecoveryViewModel(provider: store.provider, cache: env.cache)
                        env.bind(today: todayModel, recovery: recoveryModel)
                    }
            }
        } else {
            connectionPrompt
        }
    }

    /// B-33 §2b.4 + close-out: the search-role Tab hosts the WHOLE Journal — `JournalView` with the
    /// system search field and the tag scopes on top (the chrome `JournalSearchView` documents),
    /// bound straight to `JournalViewModel.filters` so typing filters the entry rows in place.
    /// On-device only, no hub gate (same as the old Journal tab).
    @ViewBuilder
    private var searchTab: some View {
        NavigationStack {
            if let journalModel {
                JournalView(model: journalModel)
                    .searchable(text: Binding(get: { journalModel.filters.query }, set: { journalModel.filters.query = $0 }), prompt: "Search entries")
                    .searchScopes(Binding(
                        get: { journalModel.filters.tag ?? JournalSearchView.allScope },
                        set: { journalModel.filters.tag = $0 == JournalSearchView.allScope ? nil : $0 }
                    )) {
                        ForEach([JournalSearchView.allScope] + journalModel.allTags, id: \.self) { tag in
                            Text(tag).tag(tag)
                        }
                    }
                    .toolbar { shellToolbar }
            } else {
                ProgressView()
                    .task {
                        let db = journalDB ?? { let d = (try? AppDatabase.onDisk()); journalDB = d; return d }()
                        let vault = journalVault ?? { let v = VaultManager(keychain: SecureKeychainService()); journalVault = v; return v }()
                        guard let db else { return }
                        journalModel = JournalViewModel(db: db, vault: vault)
                    }
            }
        }
    }

    // W3a L4 (B-13 card, tab shell): each new tab casts the hub provider to that screen's own
    // `<Screen>Providing` protocol (JICore, owned by L1/L2/L3, frozen `HealthDataProvider` +
    // siblings this wave). A cast failure — e.g. a `MockDataProvider` build that hasn't picked up
    // a given lane's conformance yet — renders `ContentUnavailableView`, never a blank tab
    // (CLAUDE.md rule 5: no silent empty state).
    @ViewBuilder
    private var energyTab: some View {
        if let store = env.providerStore {
            if let provider = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any EnergyProviding {
                if let energyModel {
                    EnergyView(model: energyModel)
                } else {
                    ProgressView()
                        .task { energyModel = EnergyViewModel(provider: provider, cache: env.cache, now: Date.init, band: env.makeEnergyBand()) }
                }
            } else {
                screenUnavailable(title: "Energy unavailable", systemImage: "flame")
            }
        } else {
            connectionPrompt
        }
    }

    @ViewBuilder
    private var nutritionTab: some View {
        if let store = env.providerStore {
            if let provider = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any NutritionProviding {
                if let nutritionModel {
                    NutritionView(model: nutritionModel)
                } else {
                    ProgressView()
                        .task { nutritionModel = NutritionViewModel(provider: provider, cache: env.cache, now: Date.init) }
                }
            } else {
                screenUnavailable(title: "Nutrition unavailable", systemImage: "fork.knife")
            }
        } else {
            connectionPrompt
        }
    }

    @ViewBuilder
    private var trainingTab: some View {
        if let store = env.providerStore {
            if let provider = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any TrainingProviding {
                if let trainingModel {
                    TrainingView(model: trainingModel)
                        .environment(\.sendToWatchModel, sendToWatchModel)
                } else {
                    ProgressView()
                        .task {
                            // B-52: the Training tab's weekday assignment is an outbox write —
                            // the same on-disk queue the weigh-in and gate rows use, with a
                            // drainer over THIS hub provider so a reachable hub still confirms
                            // in-tap. `try?`: no queue (unwritable DB) must not cost the tab, it
                            // only costs offline durability, which `assignSession` says out loud.
                            let outbox = try? Outbox(db: .onDisk())
                            trainingModel = TrainingViewModel(
                                provider: provider, healthProvider: store.provider, cache: env.cache,
                                outbox: outbox,
                                drainer: outbox.map { OutboxDrainer(outbox: $0, hub: Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider)) },
                                now: Date.init
                            )
                            sendToWatchModel = makeSendToWatchModel()
                        }
                }
            } else {
                screenUnavailable(title: "Training unavailable", systemImage: "dumbbell")
            }
        } else {
            connectionPrompt
        }
    }

    // W3b-L2 (P-kpi): both destinations need the hub provider cast to the two screen-owned
    // protocols (`NutritionProviding`, `KpiTargetsProviding`) it doesn't already carry as `any
    // HealthDataProvider` — same cast-or-`screenUnavailable` discipline as the W3a tabs above.
    @ViewBuilder
    private func kpiDetailDestination(metric: String) -> some View {
        if let store = env.providerStore, let metricId = KpiMetricId(rawValue: metric),
           let nutrition = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any NutritionProviding,
           let targets = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any KpiTargetsProviding {
            KpiDetailView(model: KpiDetailViewModel(
                metric: metricId, healthProvider: store.provider, nutritionProvider: nutrition, targetsProvider: targets, cache: env.cache,
                makeGoalsSetup: { makeGoalsSetup($0) },
                // B-57 W4: the medication the user typed + today's daytime HRV (context only).
                medicationStore: MedicationStore(prefs: env.prefs),
                daytimeHrv: Self.daytimeHrv(todayModel)
            ))
        } else {
            screenUnavailable(title: "KPI unavailable", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    @ViewBuilder
    private func kpiListDestination(onSelectKpi: ((String) -> Void)?) -> some View {
        if let store = env.providerStore,
           let nutrition = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any NutritionProviding,
           let targets = Self.hubScreensSource(hub: env.hubProvider, dataSource: store.provider) as? any KpiTargetsProviding {
            KpiListView(model: KpiListViewModel(
                healthProvider: store.provider, nutritionProvider: nutrition, targetsProvider: targets, prefStore: env.prefs, cache: env.cache
            ), onSelectKpi: onSelectKpi)
        } else {
            screenUnavailable(title: "My KPIs unavailable", systemImage: "list.bullet.rectangle")
        }
    }

    // MARK: - B-57 W2 (B-73): GoalsSetup with the phone's goals store + the save-only hub mirror

    /// Every GoalsSetup the shell builds (More, Settings, KpiDetail "Edit macro goals"): the
    /// user's nutrition goals save to `goals.macros` on this phone, and ONLY that save pushes the
    /// temporary one-way copy to the hub. The band service is never connected to the mirror, so a
    /// foreground recompute never PUTs (Review Focus 4).
    private func makeGoalsSetup(_ provider: any GoalsSetupProviding) -> GoalsSetupViewModel {
        GoalsSetupViewModel(
            provider: provider, macroStore: env.macroGoals,
            mirror: makeGoalsMirror(),   // TEMP bridge until B-50: hub weekly gate
            burnSource: { let band = env.makeEnergyBand(); band.recompute(); return band.burnWindow },
            onNutritionSaved: { Task { await env.refreshEnergyBand() } },
            // W-FIX5 DEV-15: "hub sync pending" follows the outbox (the retry scheduler delivers later).
            hubPendingSource: { (try? Outbox(db: .onDisk())).map { GoalsSetupViewModel.goalsPending(in: $0) } ?? false },
            // W-FIX5 fixer (Goals-stale): the saved document shows at once; the energy model reloads it.
            onGoalsSaved: { goals in
                savedGoals = goals
                if let energy = energyModel { Task { await energy.refresh() } }
            }
        )
    }

    // TEMP bridge until B-50: hub weekly gate
    /// W-TGT L3 (L1 hand-off): the goals copy is the ONE targets document (`/planning/goals` is
    /// read-only on the hub now).
    private func makeGoalsMirror() -> GoalsMirror? {
        guard let hub = hubScreens, let outbox = try? Outbox(db: .onDisk()) else { return nil }
        return GoalsMirror(prefs: env.prefs, outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: hub))
    }

    private func screenUnavailable(title: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("This hub connection doesn't support this screen yet.")
        }
    }

    private var connectionPrompt: some View {
        ContentUnavailableView { Label("Connect to your hub", systemImage: "server.rack") } description: { Text("Enter the HealthTraining hub URL and token.") } actions: {
            Button("Connection…") { showConnection = true }.buttonStyle(.pressableScale)
                .accessibilityIdentifier("root.connection")
        }
    }

    // W5a-L0: every optional row model `SettingsView` can link to. Hub-backed ones (goals, KPIs)
    // need the provider cast the W3/W4 destinations already use; the Backup row needs the same
    // on-disk DB + vault the Journal tab lazily builds (reused if it already did).
    private func makeSettingsModel() async -> SettingsViewModel {
        let provider = env.providerStore?.provider
        // W-FIX6 fixer F6-12/F6-12b: Goals / My KPIs (+ the KPI detail, the goals mirror) read the
        // hub whatever the data source is; the tiles' own health reads stay on the data source.
        let hub = hubScreens
        let goals = (hub as? any GoalsSetupProviding).map { makeGoalsSetup($0) }
        var kpis: KpiListViewModel?
        if let provider, let nutrition = hub as? any NutritionProviding, let targets = hub as? any KpiTargetsProviding {
            kpis = KpiListViewModel(healthProvider: provider, nutritionProvider: nutrition, targetsProvider: targets, prefStore: env.prefs, cache: env.cache)
        }
        let db = journalDB ?? (try? AppDatabase.onDisk())
        journalDB = db
        let vault = journalVault ?? VaultManager(keychain: SecureKeychainService())
        journalVault = vault
        var backup: BackupViewModel?
        if let db, let cipher = try? await vault.unlock() {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            backup = BackupViewModel(db: db, cipher: cipher, appVersion: version)
        }
        return SettingsViewModel(
            store: ConnectionConfigStore(secrets: env.secrets),
            prefs: env.prefs,
            backloadModel: HealthBackloadViewModel(runner: env.backload, hrvPrefs: env.hrvPrefs),
            healthPermissionModel: env.makeHealthPermissionModel(),
            backupModel: backup,
            goalsSetupModel: goals,
            kpiListModel: kpis,
            // W-FIX3 fixer C-e: Settings → My KPIs squares push their detail (same model as the shell's).
            makeKpiDetailModel: { metric in
                guard let provider, let nutrition = hub as? any NutritionProviding,
                      let targets = hub as? any KpiTargetsProviding else { return nil }
                return KpiDetailViewModel(metric: metric, healthProvider: provider, nutritionProvider: nutrition,
                                          targetsProvider: targets, cache: env.cache,
                                          makeGoalsSetup: { makeGoalsSetup($0) },
                                          medicationStore: MedicationStore(prefs: env.prefs),
                                          daytimeHrv: Self.daytimeHrv(todayModel))
            },
            goalsProvider: hub as? any EnergyProviding,
            todayChips: { todayModel?.squareChips ?? [] },
            syncAction: { try await env.syncNow() }
        ) { config in
            env.apply(config)
            invalidateProviderScopedModels()
        }
    }

    /// B-55 + W-FIX2 BUG-13: routed into the ORIGINATING tab's own stack, so Back returns there;
    /// a second tap inside one push animation is dropped.
    /// W-FIX2 fixer BUG-13: the Trends screen as a `RootRoute` destination, built from Today's model.
    @ViewBuilder
    private func trendsDestination(onSelectKpi: @escaping (String) -> Void) -> some View {
        if let todayModel {
            TrendsView(recovery: todayModel.recovery, daily: todayModel.gate?.daily ?? [],
                       averages: todayModel.gate?.averages, onSelectKpi: onSelectKpi)
        } else {
            screenUnavailable(title: "Trends unavailable", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    private func pushKpiDetail(_ metric: String, on tab: RootTab) {
        router.push(.kpiDetail(metric: metric), on: tab)
    }

    // MARK: - W-FIX2 DEV-04: start at the gate

    private func evaluateGate() {
        let forced = !gateForceConsumed && GateLaunch.forcedByArguments(CommandLine.arguments)
        if forced { gateForceConsumed = true }
        let last = (try? env.prefs.get(GateLaunch.lastAnsweredKey, as: String.self)) ?? nil
        if GateLaunch.shouldOpenGate(localDay: GateLaunch.localDay(Date()), lastAnsweredLocalDay: last, forced: forced) {
            openGate()
        }
    }

    /// Today at its root, showing Decide. Nothing stored is cleared: the per-verdict-date morning
    /// state and the verdict override stay as they are until the user answers.
    private func openGate() {
        selectedTab = .today
        router.popToRoot(.today)
        gateOpen = true
    }

    private func recordGateAnswered() {
        try? env.prefs.set(GateLaunch.lastAnsweredKey, GateLaunch.localDay(Date()))
    }

    /// Go / Adjust settled on the gate screen: advance a still-undecided morning, remember the
    /// day, and show the day view.
    private func answerGate(_ model: TodayViewModel) {
        if model.morningState == .decide { model.morningEvent(.gateResponded) }
        recordGateAnswered()
        gateOpen = false
    }

    /// Decide as Today's first screen — the same `DecideView` `TodayView` shows in its `.decide` state.
    /// W-FIX4 PF-01: `DecideView` is the whole screen (Go / Adjust pinned above the floating tab bar);
    /// C-f / PF-04: its pill is `syncedAt` (the Day pill's rule); BUG-30: no page title.
    @ViewBuilder
    private func gateScreen(_ model: TodayViewModel) -> some View {
        let override = overrideForVerdictDate(verdictOverrideModel?.current ?? model.morning?.verdictOverride, verdictDate: model.verdictDate)
        Group {
            if model.phase == .loaded {
                DecideView(verdict: model.verdict, readiness: model.readiness,
                           syncing: model.morning?.verdict == nil,
                           gateSignals: model.morning?.gateSignals,
                           verdictDate: model.verdictDate,
                           sessionForToday: model.morning?.sessionForToday,
                           override: override,
                           overrideModel: verdictOverrideModel,
                           syncedAt: model.syncedAt,
                           normals: decideSignalNormals(recovery: model.recovery),
                           banner: StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable),
                           calibrationNights: model.recovery.filter { KpiMetrics.nightlyHrvMs($0) != nil }.count) { answerGate(model) }
                    .environment(\.gateConfigModel, gateConfigModel)
                    .onAppear {
                        if gateConfigModel == nil {
                            // W-FIX5 W4-1: with the mirror, so a change here reaches the hub and
                            // "Not on the hub yet" clears after the foreground push.
                            _ = makeLimitsModel()
                        }
                    }
            } else {
                ScreenScroll {
                    VStack(alignment: .leading, spacing: 16) {
                        StalenessBanner(fetchedAt: model.fetchedAt, hubReachable: model.hubReachable)
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
                    .readableColumn()
                }
            }
        }
        .jiPageGround()
        .navigationTitle(Self.gateNavigationTitle(pageName: loadTodayPageName(prefs: model.tileOrderStore)))
        .navigationSubtitle(Self.gateShowsDateSubtitle ? Date().formatted(.dateTime.weekday(.wide).day().month(.wide)) : "")
        .navigationBarTitleDisplayMode(Self.gateShowsDateSubtitle ? .automatic : .inline)
        .accessibilityIdentifier("today.gate")
        .task { if !model.hasLiveResult { await model.load() } }
        .onChange(of: model.morning?.verdictOverride, initial: true) { _, fresh in
            guard let verdictOverrideModel else { return }
            if fresh != nil || verdictOverrideModel.phase != .queued { verdictOverrideModel.seed(fresh) }
        }
    }

    /// Entry point for `JournalInsightApp`'s `.onOpenURL` — resolves a parsed `DeepLink` into a
    /// tab focus + optional push via the pure `RootRoute.destination(for:)` mapping seam
    /// (`DeepLink.swift`). `.gate` has no detail screen yet, so it only focuses Today;
    /// `.kpiDetail` pushes the same route a chip tap would onto the route's owning tab (Today),
    /// deduped against its top of stack and the in-flight push guard (`TabRouter.push`).
    func handle(_ link: DeepLink) {
        // W-FIX2 DEV-04: `ji://gate` opens Decide on Today without clearing today's stored call.
        if link == .gate { openGate(); return }
        guard let route = RootRoute.destination(for: link) else { selectedTab = .today; return }
        selectedTab = TabRouter.owner(of: route)
        router.push(route)
    }
}

// W-GUI F9: `MoreChevronRow` (W-FIX2 BUG-47) is `JIChevronRow` in JIDesign now — one row for every screen.

// MARK: - Chrome-only TabView plumbing

/// Zero-size, non-interactive marker view placed inside each tab's content. On attach it walks its
/// UIKit ancestors up to the `UITabBarController`'s root view and:
///   1. clears every `backgroundColor` on the way (the content behind must show through, and the
///      glass tab bar must sample it);
///   2. disables user interaction on the tab's content container (everything under the root view
///      except the tab bar itself), so nothing there can claim a touch;
///   3. installs `PassThroughHitTest` on the root view and on the SwiftUI platform host wrapping
///      it, so a touch that does not land on an enabled subview (= the tab bar) falls through to
///      the `TabTransition` layer behind instead of being absorbed by a plain `UIView`.
/// UIKit class names in the chain are private and unstable; nothing here matches on them — only
/// on "ancestor of the placeholder" and "the view whose next responder is the tab controller".
struct TabHostPassThrough: UIViewRepresentable {
    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {}

    final class MarkerView: UIView {
        /// The view controller whose root view `view` is. SwiftUI can put its own responders (a
        /// key-press responder) between a hosting view and its controller, so this follows the
        /// responder chain past non-view responders instead of reading `view.next` alone.
        static func owningController(of view: UIView) -> UIViewController? {
            var responder = view.next
            while let r = responder, !(r is UIView) {
                if let vc = r as? UIViewController { return vc.viewIfLoaded === view ? vc : nil }
                responder = r.next
            }
            return nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // W-FIX2 BUG-14: only THIS tab's own view-controller view is disabled. The old code
            // disabled the tab controller's shared content container (the transition view every
            // tab's view lives in), so once a pass-through tab had mounted, the search-role Tab
            // (the Journal, which hosts real content) sat inside a disabled container and no
            // control on it responded until a cold start straight into Search.
            var chain: [UIView] = []
            var tabOwnView: UIView?
            var ancestor = superview
            while let view = ancestor {
                view.backgroundColor = .clear
                if tabOwnView == nil, let vc = Self.owningController(of: view),
                   vc.parent is UITabBarController || vc.parent?.parent is UITabBarController {
                    tabOwnView = view
                }
                if view.next is UITabBarController {
                    (tabOwnView ?? chain.last)?.isUserInteractionEnabled = false   // this tab's content, not the bar
                    // Every container between the tab's view and the root, the root itself and the
                    // SwiftUI platform host: a touch no enabled subview claims falls through.
                    if let tabOwnView, let i = chain.firstIndex(of: tabOwnView) {
                        for container in chain[(i + 1)...] { PassThroughHitTest.install(on: container) }
                    }
                    PassThroughHitTest.install(on: view)
                    if let host = view.superview { PassThroughHitTest.install(on: host) }
                    break
                }
                chain.append(view)
                ancestor = view.superview
            }
        }
    }
}

/// Swaps a view's class for a runtime subclass whose `hitTest(_:with:)` only ever returns a hit
/// from an enabled, visible subview — never the view itself. Idempotent per class; the subclass
/// adds nothing else, so every other behaviour of the instance is unchanged.
private enum PassThroughHitTest {
    static func install(on view: UIView) {
        let base: AnyClass = type(of: view)
        let name = "JIPassThrough_" + NSStringFromClass(base)
        if NSStringFromClass(base).hasPrefix("JIPassThrough_") { return }
        let subclass: AnyClass
        if let existing = NSClassFromString(name) {
            subclass = existing
        } else {
            guard let created = objc_allocateClassPair(base, name, 0) else { return }
            let selector = #selector(UIView.hitTest(_:with:))
            let block: @convention(block) (UIView, CGPoint, UIEvent?) -> UIView? = { view, point, event in
                MainActor.assumeIsolated {
                    guard view.isUserInteractionEnabled, !view.isHidden, view.alpha > 0.01,
                          view.point(inside: point, with: event) else { return nil }
                    for subview in view.subviews.reversed() {
                        let local = subview.convert(point, from: view)
                        if let hit = subview.hitTest(local, with: event) { return hit }
                    }
                    return nil
                }
            }
            let imp = imp_implementationWithBlock(block)
            let types = method_getTypeEncoding(class_getInstanceMethod(base, selector)!)
            class_addMethod(created, selector, imp, types)
            objc_registerClassPair(created)
            subclass = created
        }
        object_setClass(view, subclass)
    }
}

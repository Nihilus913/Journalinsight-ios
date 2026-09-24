import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub
import JIPersistence
import JIVault
import JIWorkouts

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
    static let firstLevel: [RootTab] = [.today, .recovery, .training, .more]

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
    // W5a-L0 (P-settings): the gear opens the real Settings screen (section registry, JIFeatures
    // `SettingsView`); `showConnection`/`ConnectionSheet` stay as the pre-connection sheet the
    // Today error card and `connectionPrompt` present. The model is built async (vault unlock
    // for the Backup row) the moment the sheet opens and dropped on dismiss so a saved hub
    // config or a changed KPI selection is re-read next time.
    @State private var showSettings = false
    /// B-46 item 10: "My KPIs" is presented, never pushed — see the toolbar button's comment.
    @State private var showKpiList = false
    #if DEBUG
    @State private var showDataQuality = false
    #endif
    @State private var settingsModel: SettingsViewModel?
    @State private var todayModel: TodayViewModel?
    // W5b-L2 close-out wiring: the gate-rationale screen's model, built once alongside `todayModel`
    // and routed through the environment (`GateRationaleView` reads `\.gateRationaleModel`; nil = inert).
    @State private var gateRationaleModel: GateRationaleViewModel?
    // W-B57b (B-62): Decide's verdict-override write model, built beside `gateRationaleModel`.
    @State private var verdictOverrideModel: VerdictOverrideViewModel?
    // B-37 (P-workouts): Training's "Send to Watch" sheet model; provider-scoped like the tab models.
    @State private var sendToWatchModel: SendToWatchViewModel?
    @State private var recoveryModel: RecoveryViewModel?
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
                ForEach(RootTab.firstLevel) { tab in
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
                Tab(value: RootTab.search, role: .search) {
                    searchTab
                }
                .accessibilityIdentifier(RootTab.search.accessibilityIdentifier)
            }
            .tabViewStyle(.sidebarAdaptable)   // §8.2: tab bar on iPhone, sidebar on iPad — zero code per tab
        }
        .background(theme.color(.bg))
        // B-33 §8.0: the whole shell renders in the native language; §5: tab/selection tint is
        // the personalization accent resolved for `.native`.
        .jiTheme(.native)
        .tint(AccentKey.default.color(for: .native))
        .onChange(of: ProviderSwitch.shared.revision) { _, revision in
            guard revision != providerRevision else { return }
            providerRevision = revision
            invalidateProviderScopedModels()
        }
        .onAppear { if env.needsConnection { showConnection = true } }
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
        #if DEBUG
        .sheet(isPresented: $showDataQuality) {
            NavigationStack {
                if let model = DataQualityAccess.shared.makeViewModel(cache: env.cache) { DataQualityView(model: model) } else { DataQualityUnavailableView() }
            }
        }
        #endif
        .sheet(isPresented: $showKpiList) {
            NavigationStack { kpiListDestination.navigationTitle("My KPIs") }
        }
        .sheet(isPresented: $showSettings, onDismiss: { settingsModel = nil }) {
            if let settingsModel {
                SettingsView(model: settingsModel)
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
    }

    /// Drops every view model that captured `ProviderStore.provider` at init. Deliberately does
    /// NOT drop `settingsModel`: the data-source toggle lives inside that sheet, so rebuilding it
    /// mid-flip would tear down the row the user just tapped.
    private func invalidateProviderScopedModels() {
        // Settings owns the HealthBackloadViewModel whose backloader was built on the PREVIOUS
        // HubClient — without this reset a backload after a hub-URL change still hits the old host
        // (device 2026-09-20: "network error" against a working hub).
        settingsModel = nil
        todayModel = nil
        recoveryModel = nil
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
        NavigationStack(path: Binding(get: { router.path(for: tab) }, set: { router.setPath($0, for: tab) })) {
            content()
                .toolbar { shellToolbar }
                // B-57 W1: shell hooks Recovery (L3) reads — the catalogue sheet and a KPI push.
                .environment(\.openKpiCatalogue, { showKpiList = true })
                .environment(\.openKpiDetail, { metric in pushKpiDetail(metric) })
                .navigationDestination(for: RootRoute.self) { route in
                    switch route {
                    case .kpiDetail(let metric): kpiDetailDestination(metric: metric)
                    case .kpiList: kpiListDestination
                    }
                }
        }
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
            if let todayModel {
                TodayView(
                    model: todayModel,
                    onOpenConnection: { showConnection = true },
                    onSelectKpi: { metric in pushKpiDetail(metric) },
                    makeGateRespondModel: { recommendation in makeGateRespondModel(recommendation, provider: store.provider) }
                )
                .environment(\.gateRationaleModel, gateRationaleModel)
                .environment(\.verdictOverrideModel, verdictOverrideModel)
            } else {
                ProgressView()
                    .task {
                        todayModel = TodayViewModel(provider: store.provider, cache: env.cache, prefs: env.prefs)
                        env.bind(today: todayModel, recovery: recoveryModel)
                        gateRationaleModel = GateRationaleViewModel(provider: store.provider)
                        // Outbox on the same on-disk database the drainer reads (see makeGateRespondModel).
                        if let p = store.provider as? any VerdictOverrideProviding,
                           let db = journalDB ?? { let d = (try? AppDatabase.onDisk()); journalDB = d; return d }() {
                            verdictOverrideModel = VerdictOverrideViewModel(provider: p, outbox: Outbox(db: db))
                        }
                    }
            }
        } else {
            connectionPrompt
        }
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
        List {
            Section("Track") {
                NavigationLink { nutritionTab } label: { Label("Nutrition", systemImage: RootTab.nutrition.symbol) }
                    .accessibilityIdentifier("more.nutrition")
                NavigationLink { energyTab } label: { Label("Energy", systemImage: RootTab.energy.symbol) }
                    .accessibilityIdentifier("more.energy")
                Button { showKpiList = true } label: {
                    LabeledContent { Text(Self.moreKpiText(count: moreKpiCount)) } label: { Label("My KPIs", systemImage: "chart.bar") }
                }
                    .accessibilityIdentifier("more.kpis")
                NavigationLink { moreGoals } label: { Label("Goals", systemImage: "target") }
                    .accessibilityIdentifier("more.goals")
            }
            Section("Practice") {
                NavigationLink { moreMind } label: { Label("Mind", systemImage: "water.waves") }
                    .accessibilityIdentifier("more.mind")
            }
            Section("App") {
                Button { showSettings = true } label: {
                    // Board: "Hub synced 07:41" — the last sync Today holds, or "Not synced yet".
                    LabeledContent { SyncedPill(date: todayModel?.fetchedAt) } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                }
                    .accessibilityIdentifier("more.settings")
            }
        }
        .navigationTitle("More")
        .navigationSubtitle("Everything that is not a daily decision")
    }

    @ViewBuilder private var moreGoals: some View {
        if let db = journalDB ?? (try? AppDatabase.onDisk()) {
            GoalsView(model: GoalsViewModel(store: GoalStore(db: db)))
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
            if let provider = store.provider as? any EnergyProviding {
                if let energyModel {
                    EnergyView(model: energyModel)
                } else {
                    ProgressView()
                        .task { energyModel = EnergyViewModel(provider: provider, cache: env.cache, now: Date.init) }
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
            if let provider = store.provider as? any NutritionProviding {
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
            if let provider = store.provider as? any TrainingProviding {
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
                                drainer: outbox.map { OutboxDrainer(outbox: $0, hub: store.provider) },
                                now: Date.init
                            )
                            if let templates = store.provider as? any WorkoutTemplatesProviding {
                                let sender: any WorkoutSending = CommandLine.arguments.contains("-ui-testing") ? FakeWorkoutSender() : WorkoutSchedulerSender()
                                sendToWatchModel = SendToWatchViewModel(provider: templates, sender: sender, openSettings: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                })
                            }
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
           let nutrition = store.provider as? any NutritionProviding,
           let targets = store.provider as? any KpiTargetsProviding {
            KpiDetailView(model: KpiDetailViewModel(
                metric: metricId, healthProvider: store.provider, nutritionProvider: nutrition, targetsProvider: targets, cache: env.cache
            ))
        } else {
            screenUnavailable(title: "KPI unavailable", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    @ViewBuilder
    private var kpiListDestination: some View {
        if let store = env.providerStore,
           let nutrition = store.provider as? any NutritionProviding,
           let targets = store.provider as? any KpiTargetsProviding {
            KpiListView(model: KpiListViewModel(
                healthProvider: store.provider, nutritionProvider: nutrition, targetsProvider: targets, prefStore: env.prefs, cache: env.cache
            ))
        } else {
            screenUnavailable(title: "My KPIs unavailable", systemImage: "list.bullet.rectangle")
        }
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
        let goals = (provider as? any GoalsSetupProviding).map { GoalsSetupViewModel(provider: $0) }
        var kpis: KpiListViewModel?
        if let provider, let nutrition = provider as? any NutritionProviding, let targets = provider as? any KpiTargetsProviding {
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
            todayChips: { todayModel?.squareChips ?? [] }
        ) { config in
            env.apply(config)
            invalidateProviderScopedModels()
        }
    }

    /// B-55: routed into Today's own stack; a second tap inside one push animation is dropped.
    private func pushKpiDetail(_ metric: String) {
        router.push(.kpiDetail(metric: metric))
    }

    /// Entry point for `JournalInsightApp`'s `.onOpenURL` — resolves a parsed `DeepLink` into a
    /// tab focus + optional push via the pure `RootRoute.destination(for:)` mapping seam
    /// (`DeepLink.swift`). `.gate` has no detail screen yet, so it only focuses Today;
    /// `.kpiDetail` pushes the same route a chip tap would onto the route's owning tab (Today),
    /// deduped against its top of stack and the in-flight push guard (`TabRouter.push`).
    func handle(_ link: DeepLink) {
        guard let route = RootRoute.destination(for: link) else { selectedTab = .today; return }
        selectedTab = TabRouter.owner(of: route)
        router.push(route)
    }
}

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
private struct TabHostPassThrough: UIViewRepresentable {
    func makeUIView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: MarkerView, context: Context) {}

    final class MarkerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var child: UIView = self
            var ancestor = superview
            while let view = ancestor {
                view.backgroundColor = .clear
                if view.next is UITabBarController {
                    child.isUserInteractionEnabled = false          // content container, not the bar
                    PassThroughHitTest.install(on: view)             // tab controller root view
                    if let host = view.superview { PassThroughHitTest.install(on: host) } // SwiftUI platform host
                    break
                }
                child = view
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

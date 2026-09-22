import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub
import JIPersistence
import JIVault
import JIWorkouts

// B-33 §2b.4/§5: the bar is five content tabs + the iOS 27 search role. `energy` stays in the
// vocabulary (and in `tabContent`) but is no longer one of the five — it is pushed from the
// toolbar, next to My KPIs, so Training is a first-level tab instead of living in iOS "More".
enum RootTab: Hashable, Identifiable, CaseIterable {
    case today, journal, recovery, energy, nutrition, training, search

    var id: Self { self }

    /// The five content tabs the bar shows, in order. Exactly five, so iOS never folds one into
    /// "More" — that is why `energy` is reachable from the toolbar instead (§5).
    static let firstLevel: [RootTab] = [.today, .recovery, .training, .nutrition, .journal]

    var title: String {
        switch self {
        case .today: "Today"; case .journal: "Journal"; case .recovery: "Recovery"
        case .energy: "Energy"; case .nutrition: "Nutrition"; case .training: "Training"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"; case .journal: "book.closed"; case .recovery: "heart"
        case .energy: "flame"; case .nutrition: "fork.knife"; case .training: "dumbbell"
        case .search: "magnifyingglass"
        }
    }

    /// `tab.today`, `tab.search`, … — the identifiers the UI smoke and AppTests use.
    var accessibilityIdentifier: String { "tab.\(String(describing: self))" }
}

struct RootTabView: View {
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
    @State private var settingsModel: SettingsViewModel?
    @State private var todayModel: TodayViewModel?
    // W5b-L2 close-out wiring: the gate-rationale screen's model, built once alongside `todayModel`
    // and routed through the environment (`GateRationaleView` reads `\.gateRationaleModel`; nil = inert).
    @State private var gateRationaleModel: GateRationaleViewModel?
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
    @State private var journalModel: JournalViewModel?
    @State private var selectedTab: RootTab = .today
    @State private var path: [RootRoute] = []
    // W7-L3 (P-healthkit-t2-provider): every model above that was built from `store.provider`
    // captured that provider at init, so flipping the debug data-source toggle (Settings → Data
    // source) swapped `ProviderStore.provider` while Today/Recovery/Energy/Nutrition/Training
    // kept querying the old source. `ProviderSwitch.revision` ticks once per effective provider
    // change — the toggle AND a hub reconnect — and this is the single site that invalidates the
    // cache; each tab's `.task` then rebuilds its model against the provider now in the store.
    @State private var providerRevision = 0
    // B-33 §5: Energy left the five-tab bar; it is pushed from the toolbar instead.
    @State private var showEnergy = false
    // B-33 §2b.4: the search-role Tab's query, owned here so it survives tab switches.
    @State private var journalSearchQuery = ""
    @Environment(\.jiTheme) private var theme

    var body: some View {
        NavigationStack(path: $path) {
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
                    // B-33 Contract: the search-role Tab references `JournalSearchView` by name;
                    // L6 owns the real screen (`Journal/JournalSearchView.swift`).
                    Tab(value: RootTab.search, role: .search) {
                        transparentTabContent
                    }
                    .accessibilityIdentifier(RootTab.search.accessibilityIdentifier)
                }
                .tabViewStyle(.sidebarAdaptable)   // §8.2: tab bar on iPhone, sidebar on iPad — zero code per tab
            }
            .background(theme.color(.bg))
            // W2i: the connection sheet used to be reachable only before a hub was configured or
            // from the Today error card — once connected, Settings (incl. the Health backload)
            // had no entry point. Keep it one tap away from every tab.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showEnergy = true } label: { Image(systemName: "flame") }
                        .accessibilityLabel("Energy")
                        .accessibilityIdentifier("root.energy")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(RootRoute.kpiList) } label: { Image(systemName: "list.bullet.rectangle") }
                        .accessibilityLabel("My KPIs")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("root.settings")
                }
            }
            .navigationDestination(isPresented: $showEnergy) { energyTab }
            .navigationDestination(for: RootRoute.self) { route in
                switch route {
                case .kpiDetail(let metric): kpiDetailDestination(metric: metric)
                case .kpiList: kpiListDestination
                }
            }
        }
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
        .onAppear { if let link = pendingDeepLink { handle(link); pendingDeepLink = nil } }
        .onChange(of: pendingDeepLink) { _, link in
            guard let link else { return }
            handle(link)
            pendingDeepLink = nil
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

    @ViewBuilder
    private func tabContent(_ tab: RootTab) -> some View {
        switch tab {
        case .today: todayTab
        case .journal: journalTab
        case .recovery: recoveryTab
        case .energy: energyTab
        case .nutrition: nutritionTab
        case .training: trainingTab
        case .search: searchTab
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
            } else {
                ProgressView()
                    .task {
                        todayModel = TodayViewModel(provider: store.provider, cache: env.cache, prefs: env.prefs)
                        env.bind(today: todayModel, recovery: recoveryModel)
                        gateRationaleModel = GateRationaleViewModel(provider: store.provider)
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
        NavigationStack {
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

    /// B-33 Contract: `JournalSearchView(scopes:query:)` — public, owned by L6. Scopes are the
    /// Journal's tag capsules (§2b.4); nil model = no tags yet, never a crash.
    @ViewBuilder
    private var searchTab: some View {
        NavigationStack {
            JournalSearchView(scopes: journalModel?.allTags ?? [], query: $journalSearchQuery)
        }
        .task {
            guard journalModel == nil else { return }
            let db = journalDB ?? { let d = (try? AppDatabase.onDisk()); journalDB = d; return d }()
            let vault = journalVault ?? { let v = VaultManager(keychain: SecureKeychainService()); journalVault = v; return v }()
            guard let db else { return }
            journalModel = JournalViewModel(db: db, vault: vault)
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
                            trainingModel = TrainingViewModel(provider: provider, healthProvider: store.provider, cache: env.cache, now: Date.init)
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
            kpiListModel: kpis
        ) { config in
            env.apply(config)
            invalidateProviderScopedModels()
        }
    }

    private func pushKpiDetail(_ metric: String) {
        let route = RootRoute.kpiDetail(metric: metric)
        if path.last != route { path.append(route) }
    }

    /// Entry point for `JournalInsightApp`'s `.onOpenURL` — resolves a parsed `DeepLink` into a
    /// tab focus + optional `NavigationPath` push via the pure `RootRoute.destination(for:)`
    /// mapping seam (`DeepLink.swift`). `.gate` has no detail screen yet, so it only focuses
    /// Today; `.kpiDetail` pushes the same stub a chip tap would, deduped against the current
    /// top of stack so re-opening an identical deep link doesn't stack duplicate destinations.
    func handle(_ link: DeepLink) {
        selectedTab = .today
        guard let route = RootRoute.destination(for: link) else { return }
        if path.last != route { path.append(route) }
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

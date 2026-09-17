import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub

enum RootTab: Hashable {
    case today, recovery, energy, nutrition, training
}

struct RootTabView: View {
    @Bindable var env: AppEnvironment
    /// Owned by `JournalInsightApp` (see its doc comment) so a cold-start `.onOpenURL` — which can
    /// fire before this view exists — still has somewhere to land; consumed and cleared here.
    @Binding var pendingDeepLink: DeepLink?
    @State private var showConnection = false
    @State private var todayModel: TodayViewModel?
    @State private var recoveryModel: RecoveryViewModel?
    // W3a L1–L3 (parallel lanes, PARITY P-energy/P-nutrition/P-training): the view/view-model
    // names below are the ones the wave card gives those lanes; this lane (L4) only wires the
    // tab shell around them and never edits their owned files.
    @State private var energyModel: EnergyViewModel?
    @State private var nutritionModel: NutritionViewModel?
    @State private var trainingModel: TrainingViewModel?
    @State private var selectedTab: RootTab = .today
    @State private var path: [RootRoute] = []

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
                    Tab("Today", systemImage: "sun.max", value: RootTab.today) {
                        transparentTabContent
                    }
                    Tab("Recovery", systemImage: "heart", value: RootTab.recovery) {
                        transparentTabContent
                    }
                    Tab("Energy", systemImage: "flame", value: RootTab.energy) {
                        transparentTabContent
                    }
                    Tab("Nutrition", systemImage: "fork.knife", value: RootTab.nutrition) {
                        transparentTabContent
                    }
                    Tab("Training", systemImage: "dumbbell", value: RootTab.training) {
                        transparentTabContent
                    }
                }
            }
            .background(JIColor.bg)
            // W2i: the connection sheet used to be reachable only before a hub was configured or
            // from the Today error card — once connected, Settings (incl. the Health backload)
            // had no entry point. Keep it one tap away from every tab.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showConnection = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: RootRoute.self) { route in
                switch route {
                case .kpiDetail(let metric): KpiDetailStubView(metric: metric)
                }
            }
        }
        .onAppear { if env.needsConnection { showConnection = true } }
        .onAppear { if let link = pendingDeepLink { handle(link); pendingDeepLink = nil } }
        .onChange(of: pendingDeepLink) { _, link in
            guard let link else { return }
            handle(link)
            pendingDeepLink = nil
        }
        .sheet(isPresented: $showConnection) {
            ConnectionSheet(
                store: ConnectionConfigStore(secrets: env.secrets),
                backloadModel: HealthBackloadViewModel(runner: env.backload, hrvPrefs: env.hrvPrefs),   // W2h/W2i: Garmin → Apple Health
                healthPermissionModel: env.makeHealthPermissionModel()                                  // W2d: Apple Watch → hub (dso 4)
            ) { config in
                env.apply(config)
                todayModel = nil
                recoveryModel = nil
            }
        }
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
        case .recovery: recoveryTab
        case .energy: energyTab
        case .nutrition: nutritionTab
        case .training: trainingTab
        }
    }

    @ViewBuilder
    private var todayTab: some View {
        if let store = env.providerStore {
            if let todayModel {
                TodayView(
                    model: todayModel,
                    onOpenConnection: { showConnection = true },
                    onSelectKpi: { metric in pushKpiDetail(metric) }
                )
            } else {
                ProgressView()
                    .task {
                        todayModel = TodayViewModel(provider: store.provider, cache: env.cache, prefs: env.prefs)
                        env.bind(today: todayModel, recovery: recoveryModel)
                    }
            }
        } else {
            connectionPrompt
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
                } else {
                    ProgressView()
                        .task { trainingModel = TrainingViewModel(provider: provider, cache: env.cache, now: Date.init) }
                }
            } else {
                screenUnavailable(title: "Training unavailable", systemImage: "dumbbell")
            }
        } else {
            connectionPrompt
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

/// KPI-detail placeholder — the full screen is W3 scope. Reachable both from a `TodayGrid` chip
/// tap (`onSelectKpi`) and from a `ji://kpi-detail?metric=` / `journalinsight://kpi-detail?metric=`
/// deep link, via the shared `RootRoute.kpiDetail` push.
private struct KpiDetailStubView: View {
    let metric: String

    var body: some View {
        VStack(spacing: 12) {
            Text(metric.uppercased()).font(.largeTitle.bold()).foregroundStyle(JIColor.text)
            Text("KPI detail — coming in W3").font(.subheadline).foregroundStyle(JIColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JIColor.bg)
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

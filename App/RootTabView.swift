import SwiftUI
import JICore
import JIDesign
import JIFeatures
import JIHub

enum RootTab: Hashable {
    case today, recovery
}

struct RootTabView: View {
    @Bindable var env: AppEnvironment
    /// Owned by `JournalInsightApp` (see its doc comment) so a cold-start `.onOpenURL` — which can
    /// fire before this view exists — still has somewhere to land; consumed and cleared here.
    @Binding var pendingDeepLink: DeepLink?
    @State private var showConnection = false
    @State private var todayModel: TodayViewModel?
    @State private var recoveryModel: RecoveryViewModel?
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
                        Color.clear.allowsHitTesting(false)
                    }
                    Tab("Recovery", systemImage: "heart", value: RootTab.recovery) {
                        Color.clear.allowsHitTesting(false)
                    }
                }
            }
            .background(JIColor.bg)
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
            ConnectionSheet(store: ConnectionConfigStore(secrets: env.secrets)) { config in
                env.apply(config)
                todayModel = nil
                recoveryModel = nil
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: RootTab) -> some View {
        switch tab {
        case .today: todayTab
        case .recovery: recoveryTab
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
                    .task { todayModel = TodayViewModel(provider: store.provider, cache: env.cache, prefs: env.prefs) }
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
                    .task { recoveryModel = RecoveryViewModel(provider: store.provider, cache: env.cache) }
            }
        } else {
            connectionPrompt
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

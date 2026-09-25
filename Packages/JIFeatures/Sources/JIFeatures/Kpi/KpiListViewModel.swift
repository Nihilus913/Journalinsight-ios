import Foundation
import Observation
import JICore
import JIPersistence

/// KPI list view model (W3b-L2, P-kpi). Loads the three EXISTING sections the 12 KPI_METRICS draw
/// their live values from (`HealthDataProvider.recovery`/`.gate`, `NutritionProviding.nutritionWeek`
/// — all W3a, no new hub route) plus this lane's own `KpiTargetsProviding.kpiTargets`, each
/// independently via `SectionLoader` (PARITY-7), and the on-device "My KPIs" selection via
/// `PrefStore`. Mirrors `EnergyViewModel`'s phase/error-precedence discipline (CODE-1).
@Observable @MainActor
public final class KpiListViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var recovery: [RecoveryDay] = []
    public private(set) var nutrition: [NutritionDailyRow] = []
    public private(set) var dailyRows: [DailyKpiRow] = []
    public private(set) var gateAverages: GateAverages?
    public private(set) var targets: [KpiTarget] = []
    public private(set) var prefs: KpiSelectionPrefs = KpiSelection.defaultPrefs()
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    public private(set) var hasLiveResult = false
    public private(set) var lastError: HubError?

    /// W8-L4: DESIGN-7 `ScreenState`, resolved from `phase`/`lastError` (never a second state
    /// machine). This screen's `Phase` has no `.empty` and no verdict date, so only
    /// idle/loading/loaded/error/yazioAuthExpired can arise.
    public var screenState: ScreenState {
        ScreenState.resolve(phase: mappedPhase, neverSynced: false, verdictDate: nil, todayDateString: "", lastError: lastError)
    }

    private var mappedPhase: TodayViewModel.Phase {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .error(let message): .error(message)
        }
    }

    private let healthProvider: any HealthDataProvider
    private let nutritionProvider: any NutritionProviding
    private let targetsProvider: any KpiTargetsProviding
    private let prefStore: PrefStore
    private let cache: OfflineCache
    private let now: () -> Date
    /// W-B34 L1: the `OfflineCache` key the last-fetched `[NutritionDailyRow]` lives under —
    /// public so `AppEnvironment.publishSnapshot` can fill the widget snapshot's nutrition KPIs
    /// from cache (never a new fetch).
    public nonisolated static let nutritionCacheKey = "kpi.nutrition"
    private static let keys = (recovery: "kpi.recovery", nutrition: nutritionCacheKey, gate: "kpi.gate", targets: "kpi.targets")

    public init(
        healthProvider: any HealthDataProvider,
        nutritionProvider: any NutritionProviding,
        targetsProvider: any KpiTargetsProviding,
        prefStore: PrefStore,
        cache: OfflineCache,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.healthProvider = healthProvider
        self.nutritionProvider = nutritionProvider
        self.targetsProvider = targetsProvider
        self.prefStore = prefStore
        self.cache = cache
    }

    public var visibleOrder: [KpiMetricId] { KpiSelection.visibleOrder(prefs) }

    /// W-FIX1 BUG-05: the latest reading WITH its day, so the My KPIs squares can say "as of Sep 12"
    /// instead of passing an old number off as today's.
    public func value(for id: KpiMetricId) -> KpiReading? {
        // W-FIX1 BUG-12: Load is "—" once it is not current; the rest keep their "as of" date.
        KpiMetrics.currentReading(for: id, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows,
                                  gateAverages: gateAverages, now: now())
            .map { KpiReading(value: $0.value, date: $0.date) }
    }

    public func targetText(for id: KpiMetricId) -> String? {
        KpiMetrics.targetText(for: id, targets: targets)
    }

    public func load() async {
        phase = .loading
        loadPrefs()
        restoreFromCache()
        await fetchLive()
    }

    public func refresh() async { await fetchLive() }

    // MARK: - Selection (PrefStore-backed, writes through on every change)

    @discardableResult
    public func toggle(_ id: KpiMetricId, selected: Bool) -> Bool {
        let result = KpiSelection.setSelected(prefs, id: id, selected: selected)
        guard result != prefs else { return false }
        prefs = result
        savePrefs()
        return true
    }

    public func move(_ id: KpiMetricId, direction: Int) {
        let result = KpiSelection.move(prefs, id: id, direction: direction)
        guard result != prefs else { return }
        prefs = result
        savePrefs()
    }

    public func resetSelection() {
        prefs = KpiSelection.defaultPrefs()
        savePrefs()
    }

    private func loadPrefs() {
        let raw = try? prefStore.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self)
        prefs = KpiSelection.reconcile(raw ?? nil)
    }

    private func savePrefs() { try? prefStore.set(KpiSelection.prefKey, prefs) }

    // MARK: - Live data

    private func restoreFromCache() {
        if let hit = try? cache.get(Self.keys.recovery, as: [RecoveryDay].self) { recovery = hit.value; fetchedAt = hit.fetchedAt }
        if let hit = try? cache.get(Self.keys.nutrition, as: [NutritionDailyRow].self) { nutrition = hit.value }
        if let hit = try? cache.get(Self.keys.gate, as: GateResponse.self) { dailyRows = hit.value.daily; gateAverages = hit.value.averages }
        if let hit = try? cache.get(Self.keys.targets, as: [KpiTarget].self) { targets = hit.value }
        if hasAnyData { phase = .loaded }
    }

    private func fetchLive() async {
        do {
            let health = healthProvider
            let nutritionProvider = self.nutritionProvider
            let targetsProvider = self.targetsProvider
            let cache = self.cache
            async let rR = SectionLoader.load(key: Self.keys.recovery, cache: cache) { try await health.recovery(windowDays: 28) }
            async let nR = SectionLoader.load(key: Self.keys.nutrition, cache: cache) { try await nutritionProvider.nutritionWeek(windowDays: 28) }
            async let gR = SectionLoader.load(key: Self.keys.gate, cache: cache) { try await health.gate(windowDays: 28) }
            async let tR = SectionLoader.load(key: Self.keys.targets, cache: cache) { try await targetsProvider.kpiTargets() }
            let (r, n, g, t) = try await (rR, nR, gR, tR)

            if let rv = r.value { recovery = rv }
            if let nv = n.value { nutrition = nv }
            if let gv = g.value { dailyRows = gv.daily; gateAverages = gv.averages }
            if let tv = t.value { targets = tv }
            fetchedAt = r.fetchedAt ?? fetchedAt

            let errors = [r.error, n.error, g.error, t.error].compactMap { $0 }
            let representative = errors.first { if case .unauthorized = $0 { return true }; return false }
                ?? errors.first { if case .network = $0 { return true }; return false }
                ?? errors.first
            lastError = representative

            switch representative {
            case .some(.unauthorized):
                hubReachable = true
                phase = .error(Self.describe(representative!))
            case .some(.network):
                hubReachable = false
                phase = hasAnyData ? .loaded : .error(Self.describe(representative!))
            case .some(let err):
                hubReachable = true
                phase = hasAnyData ? .loaded : .error(Self.describe(err))
            case .none:
                hubReachable = true
                hasLiveResult = true
                phase = .loaded
            }
        } catch {
            if Task.isCancelled { if phase == .loading { phase = .idle }; return }
            lastError = (error as? HubError) ?? .decoding("\(error)")
            hubReachable = true
            phase = hasAnyData ? .loaded : .error(Self.describe(error))
        }
    }

    private var hasAnyData: Bool { !recovery.isEmpty || !nutrition.isEmpty || !dailyRows.isEmpty }

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}

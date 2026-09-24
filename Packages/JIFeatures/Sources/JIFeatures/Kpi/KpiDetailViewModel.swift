import Foundation
import Observation
import JICore
import JIPersistence

/// KPI detail view model (W3b-L2, P-kpi). One metric's history (Swift Charts) + its matching gate
/// rule(s), with an inline threshold editor that round-trips through
/// `KpiTargetsProviding.updateKpiTarget` (PUT). Same section-loading/error-precedence discipline as
/// `KpiListViewModel`/`EnergyViewModel`.
@Observable @MainActor
public final class KpiDetailViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, error(String) }

    public let metric: KpiMetricId
    public private(set) var phase: Phase = .idle
    public private(set) var recovery: [RecoveryDay] = []
    public private(set) var nutrition: [NutritionDailyRow] = []
    public private(set) var dailyRows: [DailyKpiRow] = []
    public private(set) var gateAverages: GateAverages?
    /// The single gate rule this screen edits — when a metric's `targetMetricKeys` matches more
    /// than one rule (e.g. `acwr`'s three), the first match; editing multiple rules for one metric
    /// is out of this wave's scope (RN's own `app/gate-config.tsx` handles the full rule list and
    /// isn't part of this card).
    public private(set) var target: KpiTarget?
    /// The user's goals document (macro goals for the nutrition variant). `nil` = not loaded or
    /// no goals provider — the screen then says "no goal set", never invents one.
    public private(set) var goals: Goals?
    public private(set) var hubReachable = true
    /// When this metric's own source last reached the phone (nutrition for the macros, recovery
    /// otherwise). Nil until one has — the pill then says so rather than inventing a time.
    public private(set) var fetchedAt: Date?
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
    public private(set) var saving = false
    public private(set) var saveError: String?

    private let healthProvider: any HealthDataProvider
    private let nutritionProvider: any NutritionProviding
    private let targetsProvider: any KpiTargetsProviding
    private let goalsProvider: (any EnergyProviding)?
    private let cache: OfflineCache
    private static let keys = (recovery: "kpidetail.recovery", nutrition: "kpidetail.nutrition", gate: "kpidetail.gate", targets: "kpi.targets", goals: "kpidetail.goals")

    public init(
        metric: KpiMetricId,
        healthProvider: any HealthDataProvider,
        nutritionProvider: any NutritionProviding,
        targetsProvider: any KpiTargetsProviding,
        cache: OfflineCache,
        goalsProvider: (any EnergyProviding)? = nil
    ) {
        // The hub provider serves both protocols (the idiom `WeeklyPlanNutritionRow` uses).
        self.goalsProvider = goalsProvider ?? (nutritionProvider as? any EnergyProviding)
        self.metric = metric
        self.healthProvider = healthProvider
        self.nutritionProvider = nutritionProvider
        self.targetsProvider = targetsProvider
        self.cache = cache
    }

    public var def: KpiMetricDef { KpiMetrics.def(metric) }
    public var value: Double? { latest?.value }
    /// B-46 item 3: the latest NON-NULL reading and the day it came from.
    public var latest: (value: Double, date: String)? {
        KpiMetrics.latest(for: metric, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows, gateAverages: gateAverages)
    }
    /// "as of Sep 21" when the headline number is not from today; nil when it is (or when the
    /// value is the weight average, which has no single day).
    public var asOfLabel: String? { kpiAsOfLabel(valueDate: latest?.date, today: todayDateString) }
    private var todayDateString: String { String(Date().ISO8601Format().prefix(10)) }
    public var history: [(date: String, value: Double?)] { KpiMetrics.history(for: metric, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows) }

    public func load() async {
        phase = .loading
        restoreFromCache()
        await fetchLive()
    }

    public func refresh() async { await fetchLive() }

    private func restoreFromCache() {
        let targetKeys = def.targetMetricKeys
        let macro = isNutritionKpi(metric)
        if let hit = try? cache.get(Self.keys.recovery, as: [RecoveryDay].self) { recovery = hit.value; if !macro { fetchedAt = hit.fetchedAt } }
        if let hit = try? cache.get(Self.keys.nutrition, as: [NutritionDailyRow].self) { nutrition = hit.value; if macro { fetchedAt = hit.fetchedAt } }
        if let hit = try? cache.get(Self.keys.gate, as: GateResponse.self) { dailyRows = hit.value.daily; gateAverages = hit.value.averages }
        if let hit = try? cache.get(Self.keys.targets, as: [KpiTarget].self) { target = hit.value.first { targetKeys.contains($0.metric) } }
        if macro, let hit = try? cache.get(Self.keys.goals, as: Goals.self) { goals = hit.value }
        if hasAnyData { phase = .loaded }
    }

    private func fetchLive() async {
        let windowDays = min(365, def.maxLiveWindowDays)
        let targetKeys = def.targetMetricKeys
        do {
            let health = healthProvider
            let nutritionProvider = self.nutritionProvider
            let targetsProvider = self.targetsProvider
            let cache = self.cache
            async let rR = SectionLoader.load(key: Self.keys.recovery, cache: cache) { try await health.recovery(windowDays: windowDays) }
            async let nR = SectionLoader.load(key: Self.keys.nutrition, cache: cache) { try await nutritionProvider.nutritionWeek(windowDays: windowDays) }
            async let gR = SectionLoader.load(key: Self.keys.gate, cache: cache) { try await health.gate(windowDays: windowDays) }
            async let tR = SectionLoader.load(key: Self.keys.targets, cache: cache) { try await targetsProvider.kpiTargets() }
            let (r, n, g, t) = try await (rR, nR, gR, tR)
            // Goals only matter on the nutrition variant; a failure there is not a screen error
            // (the hero then says "no goal set").
            if isNutritionKpi(metric), let goalsProvider {
                if let hit = try? await SectionLoader.load(key: Self.keys.goals, cache: cache, fetch: { try await goalsProvider.goals() }),
                   let gv = hit.value { goals = gv }
            }

            if let rv = r.value { recovery = rv }
            if let nv = n.value { nutrition = nv }
            if let gv = g.value { dailyRows = gv.daily; gateAverages = gv.averages }
            if let tv = t.value { target = tv.first { targetKeys.contains($0.metric) } }
            fetchedAt = (isNutritionKpi(metric) ? n.fetchedAt : (r.fetchedAt ?? g.fetchedAt)) ?? fetchedAt

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

    /// `PUT /api/v1/planning/kpi-targets/{id}` round trip — the inline editor's only write path.
    /// A failure leaves `target` untouched and surfaces the hub's own `detail` verbatim via
    /// `saveError` (never a silently-swallowed failure, CLAUDE.md rule 4).
    public func saveThreshold(_ newThreshold: Double) async {
        guard let target else { return }
        saving = true
        saveError = nil
        do {
            let updated = try await targetsProvider.updateKpiTarget(
                id: target.targetId, threshold: newThreshold, thresholdHi: target.thresholdHi, description: target.description
            )
            self.target = updated
            // Re-fetch the full list rather than caching a synthetic one-row array under the key
            // `KpiListViewModel` also reads — a partial overwrite here would corrupt its cache.
            if let full = try? await targetsProvider.kpiTargets() {
                try? cache.put(Self.keys.targets, full)
            }
        } catch {
            saveError = Self.describe(error)
        }
        saving = false
    }

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}

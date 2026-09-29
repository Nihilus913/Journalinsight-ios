import Foundation
import Observation
import JICore
import JICompute
import JIDesign
import JIPersistence

/// KPI detail view model (W3b-L2, P-kpi). One metric's history (Swift Charts) + its matching gate
/// rule(s). Same section-loading/error-precedence discipline as `KpiListViewModel`/`EnergyViewModel`.
/// W-FIX10 F10-1: the threshold write (`saveThreshold` → `PUT /kpi-targets/{id}`, removed hub-side,
/// no call site) is gone; a rule threshold is edited in Targets › Rules.
@Observable @MainActor
public final class KpiDetailViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, error(String) }

    /// The metric on screen. BUG-22 (W-FIX2): the nutrition segment switches it between the four
    /// macros (`selectMetric`), so title, trend and alert all follow — never only the hero.
    public private(set) var metric: KpiMetricId
    public private(set) var phase: Phase = .idle
    public private(set) var recovery: [RecoveryDay] = []
    /// W-FIX7 N-1: the macro rows Apple Health first — Health's day totals on every day Health has
    /// food, the hub's YAZIO rows only for the days it lacks. `hubNutrition` = as fetched.
    public private(set) var nutrition: [NutritionDailyRow] {
        get { NutritionDailyRow.mergingHealth(hubNutrition, health: health.totals) }
        set { hubNutrition = newValue }
    }
    private var hubNutrition: [NutritionDailyRow] = []
    private var health: HealthTotalsSource
    public private(set) var dailyRows: [DailyKpiRow] = []
    public private(set) var gateAverages: GateAverages?
    /// The single gate rule this screen edits — when a metric's `targetMetricKeys` matches more
    /// than one rule (e.g. `acwr`'s three), the first match; editing multiple rules for one metric
    /// is out of this wave's scope (RN's own `app/gate-config.tsx` handles the full rule list and
    /// isn't part of this card).
    public var target: KpiTarget? {
        let keys = def.targetMetricKeys
        return targets.first { keys.contains($0.metric) }
    }
    /// Every gate rule (`/planning/kpi-targets`); `target` picks this metric's, so a segment switch
    /// re-resolves the alert without a refetch.
    private var targets: [KpiTarget] = []
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

    private let healthProvider: any HealthDataProvider
    private let nutritionProvider: any NutritionProviding
    private let targetsProvider: any KpiTargetsProviding
    private let goalsProvider: (any EnergyProviding)?
    private let cache: OfflineCache
    /// B-57 W2 (B-73): builds the "Edit macro goals" GoalsSetup with the phone's goals store and
    /// the save-only hub mirror (App wiring). nil = a bare model (no nutrition save).
    private let makeGoalsSetup: (@MainActor (any GoalsSetupProviding) -> GoalsSetupViewModel)?
    /// B-57 W4: the medication the user typed (Reminders / onboarding) and today's daytime HRV —
    /// context only (B-65), never gating; the hold is display state and changes no verdict.
    private let medicationStore: MedicationStore?
    public private(set) var medication: MedicationEntry?
    public let daytimeHrv: Double?
    private static let keys = (recovery: "kpidetail.recovery", nutrition: "kpidetail.nutrition", gate: "kpidetail.gate", targets: "kpi.targets", goals: "kpidetail.goals", load: "kpidetail.load",
                               calibration: "kpidetail.calibration")

    /// W-FIX10 R-04: the hub's baseline verdict (`/vitals/recovery-inputs` `calibration`, HT DH-4)
    /// for HRV / RHR. nil = not loaded / older hub / other metric — the phone's own band stands.
    public private(set) var calibration: RecoveryCalibration?
    /// "Calibrating · 4 of 14 nights" while the hub calibrates this metric's normal, else nil.
    public var calibrationCaption: String? {
        kpiCalibrationKey(metric).flatMap { recoveryCalibrationCaption(calibration, key: $0) }
    }

    public init(
        metric: KpiMetricId,
        healthProvider: any HealthDataProvider,
        nutritionProvider: any NutritionProviding,
        targetsProvider: any KpiTargetsProviding,
        cache: OfflineCache,
        goalsProvider: (any EnergyProviding)? = nil,
        makeGoalsSetup: (@MainActor (any GoalsSetupProviding) -> GoalsSetupViewModel)? = nil,
        medicationStore: MedicationStore? = nil,
        daytimeHrv: Double? = nil,
        healthFeed: HealthDailyTotalsFeed = .shared
    ) {
        self.health = HealthTotalsSource(feed: healthFeed)
        self.medicationStore = medicationStore
        self.daytimeHrv = daytimeHrv
        self.makeGoalsSetup = makeGoalsSetup
        // The hub provider serves both protocols (the idiom `WeeklyPlanNutritionRow` uses).
        self.goalsProvider = goalsProvider ?? (nutritionProvider as? any EnergyProviding)
        self.metric = metric
        self.healthProvider = healthProvider
        self.nutritionProvider = nutritionProvider
        self.targetsProvider = targetsProvider
        self.cache = cache
    }

    public var def: KpiDetailDef { showsLoadMinutes ? kpiLoadMinutesDef : KpiDetailDef(KpiMetrics.def(metric)) }
    public var value: Double? { latest?.value }
    /// B-46 item 3: the latest NON-NULL reading and the day it came from.
    public var latest: (value: Double, date: String)? {
        // WD-1: the 7-day Load is "today's" reading (it ends yesterday by definition) — no "as of".
        if showsLoadMinutes, let loadReading { return (loadReading.minutes, loadToday) }
        return KpiMetrics.latest(for: metric, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows, gateAverages: gateAverages)
    }

    // MARK: - W-FIX5 L1 (WD-1): the gate-input Load

    /// The 7-day Load minutes + band the Today / Recovery Load square shows
    /// (`recoveryLoadReading` over `/vitals/recovery-inputs`, the same 42-day window). nil for any
    /// other metric, a provider without the route, or too few logged days.
    public private(set) var loadReading: RecoveryLoadReading?
    private var loadDays: [RecoveryInputDay] = []
    private var loadToday = ""
    /// The Load detail shows minutes exactly when the Today square does: no current ACWR
    /// (`KpiMetrics.currentAcwr`, ≤ 36 h — a stale "0.12 as of 10 Sep" never wins) and a reading.
    public var showsLoadMinutes: Bool {
        metric == .acwr && loadReading != nil && KpiMetrics.currentAcwr(recovery, now: Date()) == nil
    }
    /// "as of Sep 21" when the headline number is not from today; nil when it is (or when the
    /// value is the weight average, which has no single day).
    public var asOfLabel: String? { kpiAsOfLabel(valueDate: latest?.date, today: todayDateString) }
    private var todayDateString: String { String(Date().ISO8601Format().prefix(10)) }
    public var history: [(date: String, value: Double?)] {
        if showsLoadMinutes { return kpiLoadHistory(days: loadDays, today: loadToday) }
        return KpiMetrics.history(for: metric, recovery: recovery, nutrition: nutrition, dailyRows: dailyRows)
    }

    /// BUG-22: the nutrition segment. Only switches between nutrition macros (they share one data
    /// source, so nothing refetches); any other metric is ignored.
    public func selectMetric(_ newMetric: KpiMetricId) {
        guard newMetric != metric, isNutritionKpi(metric), isNutritionKpi(newMetric) else { return }
        metric = newMetric
    }

    /// BUG-40: "Edit macro goals" → Goals setup, when the provider speaks `GoalsSetupProviding`
    /// (the hub does); nil otherwise, and the link is not shown. Built once.
    public var goalsSetupModel: GoalsSetupViewModel? {
        if let cachedGoalsSetupModel { return cachedGoalsSetupModel }
        guard let provider = nutritionProvider as? any GoalsSetupProviding else { return nil }
        let model = makeGoalsSetup?(provider) ?? GoalsSetupViewModel(provider: provider)
        cachedGoalsSetupModel = model
        return model
    }
    @ObservationIgnored private var cachedGoalsSetupModel: GoalsSetupViewModel?
    #if DEBUG
    /// Test seam (BUG-09): how many `KpiDetailView` body evaluations rendered this model. Per
    /// instance, so tests hosting KpiDetail in parallel never see each other's renders.
    @ObservationIgnored var debugRenderCount = 0
    #endif

    // MARK: - B-57 W4 daytime HRV + medication check (manual entry)

    public func loadMedication() { medication = medicationStore?.load() }
    public var daytimeState: DaytimeHrvState { daytimeHrvState(medication) }
    public var showsMedicationCard: Bool { metric == .hrv && (medication?.isNamed ?? false) }
    /// "—" + "No data" when there is no reading — never a zero (rule 5).
    public var daytimeValueText: String { daytimeHrv.map { "\(Int($0.rounded())) ms" } ?? "—" }
    public var daytimeReason: String? { daytimeHrv == nil ? JIMissingReason.noData.rawValue : nil }
    public var medicationCardBody: String {
        "You added \(medication?.name ?? ""). Some medications raise heart rate and lower HRV while they work. Is it yours and current?"
    }

    public func answerMedication(_ yes: Bool) {
        guard var m = medication else { return }
        m.answer = yes ? .yes : .no
        medication = m
        try? medicationStore?.save(m)
    }

    public func resetMedicationAnswer() {
        guard var m = medication else { return }
        m.answer = .unconfirmed
        medication = m
        try? medicationStore?.save(m)
    }

    public func load() async {
        loadMedication()
        phase = .loading
        restoreFromCache()
        await fetchLive()
    }

    public func refresh() async { await fetchLive() }

    /// W-TGT fixer 1c: "Your normal" for Settings › Targets' editor, from the history this phone
    /// already holds (KPI detail's cache, else the My KPIs cache; Apple Health day totals first) —
    /// the same `targetNormalInfo` KPI detail's own sheet shows, so the two doors never disagree.
    public static func cachedTargetNormal(_ subject: TargetSubject, cache: OfflineCache,
                                          healthFeed: HealthDailyTotalsFeed = .shared,
                                          today: String = RecoveryInsightService.localDayKey(Date())) -> TargetNormalInfo? {
        guard let metric = targetsNormalMetric(subject) else { return nil }
        func rows<T: Decodable & Sendable>(_ keys: [String], _ type: T.Type) -> T? {
            for key in keys { if let hit = try? cache.get(key, as: type) { return hit.value } }
            return nil
        }
        var health = HealthTotalsSource(feed: healthFeed)
        health.restore(from: cache)
        let recovery = rows([keys.recovery, "kpi.recovery"], [RecoveryDay].self) ?? []
        let hubNutrition = rows([keys.nutrition, KpiListViewModel.nutritionCacheKey], [NutritionDailyRow].self) ?? []
        let daily = rows([keys.gate, "kpi.gate"], GateResponse.self)?.daily ?? []
        let nutrition = NutritionDailyRow.mergingHealth(hubNutrition, health: health.totals)
        let points = KpiMetrics.history(for: metric, recovery: recovery, nutrition: nutrition, dailyRows: daily)
        let def = KpiDetailDef(KpiMetrics.def(metric))
        return targetNormalInfo(points: points, today: today, decimals: def.decimals, unit: def.unit)
    }

    private func restoreFromCache() {
        health.restore(from: cache)
        let macro = isNutritionKpi(metric)
        if let hit = try? cache.get(Self.keys.recovery, as: [RecoveryDay].self) { recovery = hit.value; if !macro { fetchedAt = hit.fetchedAt } }
        if let hit = try? cache.get(Self.keys.nutrition, as: [NutritionDailyRow].self) { nutrition = hit.value; if macro { fetchedAt = hit.fetchedAt } }
        if let hit = try? cache.get(Self.keys.gate, as: GateResponse.self) { dailyRows = hit.value.daily; gateAverages = hit.value.averages }
        if let hit = try? cache.get(Self.keys.targets, as: [KpiTarget].self) { targets = hit.value }
        if macro, let hit = try? cache.get(Self.keys.goals, as: Goals.self) { goals = hit.value }
        if kpiCalibrationKey(metric) != nil, let hit = try? cache.get(Self.keys.calibration, as: RecoveryCalibration.self) {
            calibration = hit.value
        }
        if metric == .acwr, let hit = try? cache.get(Self.keys.load, as: [RecoveryInputDay].self) {
            adoptLoad(hit.value, today: RecoveryInsightService.localDayKey(Date()))
        }
        if hasAnyData { phase = .loaded }
    }

    private func fetchLive() async {
        let windowDays = min(365, def.maxLiveWindowDays)
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
            // WD-1: the Load detail also reads the gate's own inputs (the Load square's source). A
            // failure is not a screen error — the ACWR path (or "No data") stays.
            if metric == .acwr, let inputs = health as? any RecoveryInputsProviding {
                let day = RecoveryInsightService.localDayKey(Date())
                if let hit = try? await SectionLoader.load(key: Self.keys.load, cache: cache, fetch: {
                    try await inputs.recoveryInputs(date: day, windowDays: RecoveryInsightService.windowDays)
                }), let days = hit.value { adoptLoad(days, today: day) }
            }
            // W-FIX10 R-04: HRV / RHR read the hub's calibration verdict; a failure keeps the cached one.
            if kpiCalibrationKey(metric) != nil, let inputs = health as? any RecoveryInputsProviding {
                let day = RecoveryInsightService.localDayKey(Date())
                if let report = try? await inputs.recoveryInputsReport(date: day, windowDays: RecoveryInsightService.windowDays) {
                    calibration = report.calibration
                    if let c = report.calibration { try? cache.put(Self.keys.calibration, c) }
                }
            }
            if isNutritionKpi(metric), let goalsProvider {
                if let hit = try? await SectionLoader.load(key: Self.keys.goals, cache: cache, fetch: { try await goalsProvider.goals() }),
                   let gv = hit.value { goals = gv }
            }

            if let rv = r.value { recovery = rv }
            if let nv = n.value { nutrition = nv }
            if let gv = g.value { dailyRows = gv.daily; gateAverages = gv.averages }
            if let tv = t.value { targets = tv }
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

    private var hasAnyData: Bool { !recovery.isEmpty || !nutrition.isEmpty || !dailyRows.isEmpty || !loadDays.isEmpty }

    private func adoptLoad(_ days: [RecoveryInputDay], today: String) {
        loadDays = days
        loadToday = today
        loadReading = recoveryLoadReading(days: days, today: today)
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

/// W-FIX10 R-04: the KPI detail's one normal — none while the hub calibrates the metric (the
/// 7-day mean stays: it is a plain average of real nights, not a band).
public nonisolated func kpiDetailNormal(points: [(date: String, value: Double?)], today: String,
                                        hubCalibrating: Bool) -> (normal: PersonalNormalResult?, sevenDay: Double?) {
    let r = KpiNormal.make(points: points, today: today)
    return hubCalibrating ? (nil, r.sevenDay) : r
}

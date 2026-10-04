import Foundation
import Observation
import JICore
import JIPersistence
import JIDesign

nonisolated public struct TodayChip: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?, unit: String?, points: [Double?], sourceMissing: Bool
    /// B-46 device feedback 3: "as of Sep 21" when `value` is a fallback from an earlier day
    /// (Garmin hasn't synced since the 18th, so today's row carries a nil HRV/RHR) — nil when the
    /// value IS today's. Explicit init with a default so existing construction sites are
    /// unchanged; the chip view renders it under the number.
    public let asOf: String?

    public init(id: String, label: String, value: Double?, unit: String?, points: [Double?], sourceMissing: Bool, asOf: String? = nil) {
        self.id = id; self.label = label; self.value = value; self.unit = unit
        self.points = points; self.sourceMissing = sourceMissing; self.asOf = asOf
    }
}

nonisolated public struct ResolvedTodayRow: Sendable { public let row: DailyKpiRow?; public let stale: Bool }

/// Port of mobile/src/data/cache/todayFallback.ts — `daily[0]` is today; a day is "real" when kcal or protein > 0.
nonisolated public func resolveTodayRow(_ daily: [DailyKpiRow]) -> ResolvedTodayRow {
    func real(_ r: DailyKpiRow?) -> Bool {
        guard let r else { return false }
        return ((r.values["kcal_consumed"] ?? nil) ?? 0) > 0 || ((r.values["protein_g"] ?? nil) ?? 0) > 0
    }
    if real(daily.first) { return ResolvedTodayRow(row: daily.first, stale: false) }
    if let fb = daily.dropFirst().first(where: real) { return ResolvedTodayRow(row: fb, stale: true) }
    return ResolvedTodayRow(row: daily.first, stale: false)
}

@Observable @MainActor
public final class TodayViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var morning: MorningResponse?
    /// W-FIX7 N-1 (Fuel): the hub's gate rows with Apple Health's food (kcal, protein, carbs,
    /// fat) on every day Health has it — Fuel and the Protein / Calories squares read Health first,
    /// YAZIO only for the days Health lacks. Every other key stays the hub's. `hubGate` = as fetched.
    public private(set) var gate: GateResponse? {
        get {
            guard var g = hubGate else { return nil }
            g.daily = DailyKpiRow.mergingHealth(g.daily, health: fuelHealth.totals)
            return g
        }
        set { hubGate = newValue }
    }
    private var hubGate: GateResponse?
    private var fuelHealth: HealthTotalsSource
    public private(set) var recovery: [RecoveryDay] = []
    /// W-FIX13 F-7 (B-69): the hub's `last_night` (newest night, Apple before Garmin) — the vitals
    /// tile and the readiness ring read it; nil (older hub / no night) = the rows path.
    public private(set) var lastNightReport: RecoveryLastNight?
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    /// True once a live fetch has actually completed (success or non-cancellation failure with cache
    /// fallback). Separate from `phase` — a warm cache can push `phase` to `.loaded` before any live
    /// fetch has run, so `TodayView` must gate its auto-reload on this, not on `phase == .idle`
    /// (CODE-1: a cancelled fetch over a warm cache must still re-fetch live on next appearance).
    public private(set) var hasLiveResult = false

    // B-57 §2 — the morning flow (Decide → Coach → Day), kept per verdict date. Advances on user
    // action only (`morningEvent`), never on the clock; re-synced whenever `morning.verdictDate` changes.
    public private(set) var morningState: TodayMorningState = .decide
    /// Fallback store when `prefs == nil` (previews, older call sites): state lives for the session.
    private var memoryMorningStates: [String: TodayMorningState] = [:]
    private var syncedVerdictDate: String?
    public var verdictDate: String? { morning?.verdictDate }

    // PARITY-7: each section's own capture time, independent of the others — a hub outage that only
    // takes down `recovery` shouldn't make `morning`'s freshly-fetched data look stale, or vice versa.
    public private(set) var morningFetchedAt: Date?
    public private(set) var gateFetchedAt: Date?
    public private(set) var recoveryFetchedAt: Date?
    /// The typed error from whichever section's failure currently drives `phase`/`hubReachable` (see
    /// `fetchLive`'s `representative` selection) — `nil` after a fully clean fetch. Feeds `screenState`'s
    /// `.yazioAuthExpired` refinement without `phase` itself needing a case for every named `HubError`.
    public private(set) var lastError: HubError?

    private let provider: any HealthDataProvider
    /// W-FIX6 F6-11 (S1): the ONE source of the morning call — the hub's `/planning/morning`. The
    /// tiles' data source (`provider`) may be the on-device T2 provider, which has no verdict
    /// (`notCapable(.gate)`); asking it left Decide, the widget and the Live Activity on a four-day-old
    /// cached call. The gate rows follow the same rule when the data source cannot serve them.
    private let verdictProvider: any HealthDataProvider
    private let cache: OfflineCache
    /// Optional — nil at call sites that haven't wired tile-order persistence yet (e.g. pre-W2b
    /// `RootTabView`). `TodayGrid` degrades gracefully to an unpersisted default order when nil.
    private let prefs: PrefStore?
    private let now: () -> Date
    /// W-KEYS K2: the day's zone — the phone's (D1); injectable for tests.
    private let zone: () -> TimeZone
    private static let keys = (morning: "today.morning", gate: "today.gate", recovery: "today.recovery", sleepSummary: "today.sleepSummary",
                               exercises: "today.exercises", planSessions: "today.planSessions", verdictReason: "today.verdictReason",
                               planWeek: "today.planWeek", hubLastSync: "today.hubLastSync",
                               lastNight: lastNightCacheKey)
    nonisolated private static let lastNightCacheKey = "today.lastNight"

    /// W-FIX10 R-01: the active plan's sessions (`GET /planning/plan-sessions`) — the one schedule
    /// resolver (`scheduledSession`) reads today's session from their weekdays. Empty = no plan read
    /// (not a `TrainingProviding`, an older hub, or never answered); a failure keeps the last rows.
    public private(set) var planSessions: [PlanSessionOut] = []
    /// W-SSOT-1 SS-7: the hub's served week (`GET /planning/week?start=`) — preferred over the rows
    /// above; nil when the hub does not serve it (older hub) or it was never read.
    public private(set) var planWeek: PlanWeekOut?

    /// W-FIX10 R-01: today's session from the plan's weekdays (what the day sheet moves — the rule
    /// the hub's morning call follows). nil when no plan was read: the hub's labels stand.
    public var scheduledSessionToday: String? {
        guard !planSessions.isEmpty || planWeek != nil else { return nil }
        return scheduledSession(on: todayDateString, planSessions: planSessions, week: planWeek)?.name
    }

    /// W-FIX10 R-05: the persisted reason of the verdict date's call (`/planning/morning-verdict`).
    public private(set) var verdictReason: String?

    /// W-FIX10 R-05: "Waiting for the watch…" while the hub holds the morning push (nil otherwise).
    public var heldReason: String? { decideHeldReason(verdictReason) }

    /// W-FIX4 PF-02: the hub's plan (`/planning/exercises`, the rows Training lists) — Day's NEXT card
    /// names today's exercises and working weights from it. Empty when the provider has no plan
    /// (not a `TrainingProviding`) or never answered; a failure keeps the last known rows.
    public private(set) var exercises: [Exercise] = []

    /// W-B81 A-5: today's completed workouts from the hub (`/training/day/{today}` — Apple dso 4 and
    /// Garmin), for Day's NEXT card. Same cache key as Training's day detail. Empty when the provider
    /// has no training routes; a failure keeps the last known rows.
    public var hubWorkouts: [DayActivity] { hubDay?.activities ?? [] }
    /// W-FIX9 G3: the whole `/training/day/{today}` answer — its logged sets feed NEXT's
    /// logged-vs-planned lift rows (C-3). nil until the hub answered.
    public private(set) var hubDay: TrainingDayDetail?
    /// Today's logged sets from the hub (empty = none logged, or no hub answer yet).
    public var hubExerciseSets: [DayExerciseSet] { hubDay?.exerciseSets ?? [] }

    /// Today's weekday in the plan's numbering (Mon = 0 … Sun = 6), for the NEXT card's fallback.
    public var todayWeekday: Int {
        (Calendar(identifier: .gregorian).component(.weekday, from: now()) + 5) % 7
    }

    /// W-FIX2 L5 (FM-08, DEV-02): `/vitals/sleep-summary` — the hub's computed score for last night
    /// (Apple era), which the Sleep ring shows. `nil` when the provider cannot serve it (not a
    /// `SleepSummaryProviding`) or has never answered; the ring then keeps `RecoveryDay.sleepScore`.
    public private(set) var sleepSummary: SleepSummary?
    /// W-FIX2 L5 (DEV-03): the hub's own last ingestion sync (`/ingestion/status` `last_sync`).
    public private(set) var hubLastSync: Date?
    /// W-FIX2 L5 (DEV-03): the app's own uploader record — the last 2xx HealthKit upload POST
    /// (`hk.upload.lastSuccess`, written by JIHealthKit's `HealthKitUploader` in the App Group).
    public private(set) var lastUploadAt: Date?
    private let uploadRecord: UserDefaults?
    private static let lastUploadKey = PrefKeys.hkLastUploadSuccess

    /// W-FIX2 L5 (DEV-03): what the sync chip shows — the newer of the hub's last sync and this
    /// app's last successful HealthKit upload. `nil` ("Not synced yet") when neither is known —
    /// never the time the screen happened to fetch.
    public var syncedAt: Date? { [hubLastSync, lastUploadAt].compactMap { $0 }.max() }
    /// Whether ANY section has ever synced successfully — set once from a warm cache at `restoreFromCache`,
    /// or the first time a live fetch fully succeeds — and never cleared by a later failure. Distinguishes
    /// a truly first-ever empty response (`.neverSynced`) from an established screen going transiently
    /// blank (`.empty`).
    private var everSynced = false
    private var neverSyncedObserved = false

    /// W2c-L1 snapshot wiring seam: fired whenever `morning`/`recovery`/`chips` may have changed
    /// (end of `restoreFromCache` and end of every `fetchLive`, success or cache-fallback alike —
    /// never on the plain-cancellation early return, since nothing changed there). Kept as a bare
    /// closure rather than a `JISnapshot` dependency here: JIFeatures has no reason to depend on
    /// the widget-facing snapshot package, so the App target (which does) reads this VM's own
    /// public `verdict`/`readiness`/`chips`/`fetchedAt` and builds the `HubSnapshot` itself.
    public var onSectionUpdate: (() -> Void)?

    /// - Parameter uploadRecord: the App-Group suite holding the uploader's last-success instant
    ///   (DEV-03); tests inject a scratch suite, `nil` = no record (the chip uses the hub alone).
    /// - Parameter verdictProvider: the hub (W-FIX6 F6-11) — `/planning/morning` is always read from
    ///   it; nil = `provider` (the hub itself, previews, tests).
    public init(provider: any HealthDataProvider, verdictProvider: (any HealthDataProvider)? = nil, cache: OfflineCache,
                prefs: PrefStore? = nil, now: @escaping () -> Date = Date.init,
                uploadRecord: UserDefaults? = UserDefaults(suiteName: "group.toby913.JournalInsight"),
                healthFeed: HealthDailyTotalsFeed = .shared,
                zone: @escaping () -> TimeZone = { DayKey.zone }) {
        self.fuelHealth = HealthTotalsSource(feed: healthFeed)
        self.provider = provider; self.verdictProvider = verdictProvider ?? provider
        self.cache = cache; self.prefs = prefs; self.now = now; self.uploadRecord = uploadRecord
        self.zone = zone
    }

    /// W-FIX5 W5-4: the queue "Your week"'s weekday writes go through (B-52, the same on-disk
    /// outbox the Training tab uses). A seam so tests never open the on-disk database.
    @ObservationIgnored public var weekOutbox: () -> Outbox? = { try? Outbox(db: .onDisk()) }

    /// W-FIX5 W5-4: Day's "Week review" row opens "Your week" — a Training week model over this
    /// screen's provider and cache. nil when the provider has no training routes.
    public var makesTrainingWeekModel: Bool { provider is any TrainingProviding }

    public func makeTrainingWeekModel() -> TrainingViewModel? {
        guard let training = provider as? any TrainingProviding else { return nil }
        let outbox = weekOutbox()
        return TrainingViewModel(provider: training, healthProvider: provider, cache: cache, outbox: outbox,
                                 drainer: outbox.map { OutboxDrainer(outbox: $0, hub: provider) }, now: now)
    }

    /// The `PrefStore` `TodayGrid` persists its drag-reorder tile order to (`today.tileOrder`).
    /// `nil` at call sites that haven't wired it yet — see `prefs`'s doc comment.
    public var tileOrderStore: PrefStore? { prefs }

    /// DESIGN-7 screen state — a pure refinement of `phase` (see `ScreenState.resolve`); read this for
    /// never-synced / stale-verdict-date / yazioAuthExpired copy instead of re-deriving them from `phase`.
    public var screenState: ScreenState {
        ScreenState.resolve(phase: phase, neverSynced: neverSyncedObserved, verdictDate: morning?.verdictDate, todayDateString: todayDateString, lastError: lastError)
    }

    private var todayDateString: String { DayKey.today(now: now(), in: zone()).iso }

    public var verdict: VerdictParts { verdictParts(morning?.verdict) }

    /// W-FIX6 F6-11: the ONE headline (word, session, tone) Decide, Day, the widgets and the Live
    /// Activity show for the call in effect — `override` is the one for `verdictDate` (or nil).
    public func headline(override: VerdictOverride?) -> VerdictHeadline {
        verdictHeadline(parts: verdict, override: overrideForVerdictDate(override, verdictDate: verdictDate))
    }

    /// B-46 device feedback 3: the newest non-null reading AND the day it came from, so a chip
    /// can say "as of Sep 21" rather than presenting an older number as today's.
    private func newestNonNull<T>(_ rows: [T], date: (T) -> String, value: (T) -> Double?) -> (value: Double, date: String)? {
        for row in rows.sorted(by: { date($0) > date($1) }) {
            if let v = value(row) { return (v, date(row)) }
        }
        return nil
    }

    private func chip(_ id: String, _ label: String, unit: String?, points: [Double?], sourceMissing: Bool, latest: (value: Double, date: String)?) -> TodayChip {
        TodayChip(
            id: id, label: label, value: latest?.value, unit: unit, points: points, sourceMissing: sourceMissing,
            asOf: kpiAsOfLabel(valueDate: latest?.date, today: todayDateString)
        )
    }

    /// W-FIX1 BUG-05: "last night" means last night — the newest non-null value is kept only while
    /// that night is ≤ 36 h old (`KpiMetrics.isLastNightFresh`); older is `nil` ("—"), never a
    /// four-day-old readiness shown as today's (Day hero ring + summary line).
    private func lastNight(_ value: (RecoveryDay) -> Double?) -> (value: Double, date: String)? {
        newestNonNull(recovery, date: \.date, value: value).flatMap {
            KpiMetrics.isLastNightFresh(nightDate: $0.date, now: now()) ? $0 : nil
        }
    }

    public var readiness: Double? { lastNightReading(\.readiness, rows: \.readinessScore)?.value }

    /// F-7 (B-69): the hub's `last_night` value (that night, that source) while it is fresh; a hub
    /// that served no `last_night` falls back to the rows. Never mixes: a served night's nil
    /// (Apple calibrating) stays nil rather than borrowing an older Garmin night.
    private func lastNightReading(_ served: KeyPath<RecoveryLastNight, Double?>, rows: @escaping (RecoveryDay) -> Double?) -> (value: Double, date: String)? {
        guard let night = lastNightReport else { return lastNight(rows) }
        guard KpiMetrics.isLastNightFresh(nightDate: night.date, now: now(), in: zone()), let v = night[keyPath: served] else { return nil }
        return (v, night.date)
    }

    /// DEV-02: the sleep-summary score with its night, whatever its age.
    private var summarySleep: (value: Double, date: String)? {
        guard let s = sleepSummary, let v = s.scoreComputed, let d = s.scoreComputedDate else { return nil }
        return (v, d)
    }

    private var freshSummarySleep: (value: Double, date: String)? {
        summarySleep.flatMap { KpiMetrics.isLastNightFresh(nightDate: $0.date, now: now()) ? $0 : nil }
    }

    /// W-FIX2 L5 (DEV-01/02): the dated reading behind a Today "My KPIs" cell — the same
    /// `KpiMetrics.latest` the KPI detail uses (HRV = the night's `hrv_rmssd_ms`, never the 7-day
    /// mix), except Sleep, which is the hub's sleep-summary score when served (the hero ring's value).
    public func kpiReading(_ id: KpiMetricId) -> (value: Double, date: String)? {
        if id == .sleep, let s = summarySleep { return s }
        return KpiMetrics.latest(for: id, recovery: recovery, nutrition: [],
                                 dailyRows: gate?.daily ?? [], gateAverages: gate?.averages)
    }

    /// W-FIX1 BUG-12: the Day hero's Load ring — the newest real ACWR only while it is current
    /// (`KpiMetrics.currentAcwr`, ≤ 36 h); the ring has no room for a date, so older is "—".
    public var heroLoad: Double? { KpiMetrics.currentAcwr(recovery, now: now()) }

    public var chips: [TodayChip] {
        let caps = provider.capabilities
        let rec = recovery.sorted { $0.date < $1.date }.suffix(7)
        let daily = gate?.daily ?? []
        // PARITY-1: steps mirrors RN VerdictHero.tsx:312-323 — newest non-null `values["steps"]` over
        // date-sorted `gate.daily`. `resolveTodayRow` stays reserved for the future W2 kcal/protein
        // ring: it skips null-food rows on purpose, which lands on the wrong date for steps.
        let steps = newestNonNull(daily, date: \.date, value: { $0.values["steps"] ?? nil })
        return [
            // W-FIX1 BUG-06: last night's HRV, never `hrv_series`' 7-day `hrv_weekly_avg` mix.
            chip("hrv", "HRV", unit: "ms", points: rec.map { KpiMetrics.nightlyHrvMs($0) }, sourceMissing: !caps.contains(.hrvRMSSD),
                 latest: lastNightReading(\.hrvMs) { KpiMetrics.nightlyHrvMs($0) }),
            chip("rhr", "RHR", unit: "bpm", points: rec.map(\.rhrBpm), sourceMissing: false,
                 latest: lastNightReading(\.rhrBpm, rows: \.rhrBpm)),
            // W-FIX2 DEV-02: the hub's sleep-summary score for last night (89 on 09-25), else the
            // recovery row's own score — both under the same ≤ 36 h "last night" rule.
            chip("sleep", "Sleep", unit: nil, points: rec.map(\.sleepScore), sourceMissing: !caps.contains(.garminSleepScore) && summarySleep == nil,
                 latest: freshSummarySleep ?? lastNight(\.sleepScore)),
            chip("steps", "Steps", unit: nil, points: daily.sorted { $0.date < $1.date }.suffix(7).map { $0.values["steps"] ?? nil }, sourceMissing: false,
                 latest: steps),
        ]
    }

    /// B-57 W1 EditToday board: Today's four chips plus the squares the board adds — Load (newest
    /// ACWR), Protein and Calories (today's food row, or the latest real one with its "as of" day,
    /// `resolveTodayRow`), Weight (newest `weight_kg`). Nil stays nil: the square says why.
    /// `chips` itself is unchanged (hero sleep, widget snapshot); Today's grid reads `gridChips`.
    public var squareChips: [TodayChip] {
        let daily = gate?.daily ?? []
        let food = resolveTodayRow(daily).row
        func foodValue(_ key: String) -> (value: Double, date: String)? {
            guard let food, let v = food.values[key] ?? nil else { return nil }
            return (v, food.date)
        }
        let sortedRec = recovery.sorted { $0.date < $1.date }.suffix(7)
        let sortedDaily = daily.sorted { $0.date < $1.date }.suffix(7)
        return chips + [
            chip("acwr", "Load", unit: nil, points: sortedRec.map(\.acwr), sourceMissing: false,
                 latest: lastNight(\.acwr)),   // W-FIX1 BUG-12: a stale Load is "—", not today's
            chip("protein", "Protein", unit: "g", points: sortedDaily.map { $0.values["protein_g"] ?? nil }, sourceMissing: false,
                 latest: foodValue("protein_g")),
            chip("kcal", "Calories", unit: "kcal", points: sortedDaily.map { $0.values["kcal_consumed"] ?? nil }, sourceMissing: false,
                 latest: foodValue("kcal_consumed")),
            chip("weight", "Weight", unit: "kg", points: sortedDaily.map { $0.values["weight_kg"] ?? nil }, sourceMissing: false,
                 latest: newestNonNull(daily, date: \.date, value: { $0.values["weight_kg"] ?? nil })),
            // W-FIX3 C-a: every KPI My KPIs can put "On Today" has a square (TodayTileRegistry.optInIds).
            chip("body_battery", "Body Battery", unit: nil, points: sortedRec.map(\.bodyBatteryAvg), sourceMissing: false,
                 latest: lastNight(\.bodyBatteryAvg)),
            chip("readiness", "Readiness", unit: nil, points: sortedRec.map(\.readinessScore), sourceMissing: false,
                 latest: lastNightReading(\.readiness, rows: \.readinessScore)),
            chip("carbs", "Carbs", unit: "g", points: sortedDaily.map { $0.values["carbs_g"] ?? nil }, sourceMissing: false,
                 latest: foodValue("carbs_g")),
            chip("fat", "Fat", unit: "g", points: sortedDaily.map { $0.values["fat_g"] ?? nil }, sourceMissing: false,
                 latest: foodValue("fat_g")),
        ]
    }

    /// W-FIX2 fixer BUG-19: what Today's `TodayGrid` is handed — every EditToday square (the grid
    /// then filters/orders them by EditToday's prefs), so EditToday's 8 of 8 = Today's 8 tiles.
    public var gridChips: [TodayChip] { squareChips }

    public func load() async {
        // W-FIX3 C-a: fold EditToday's set into the one selection before any screen (the gate, My
        // KPIs) reads it — a no-op once unified.
        _ = loadTodayTilePrefs(prefs: prefs)
        phase = .loading
        restoreFromCache()
        // W-FIX7 F7-1: today's Apple Health workouts (session done) before the hub answers.
        await TodayWorkoutsModel.shared.refresh()
        await fetchLive()
    }

    /// Toby 2026-10-01: pull-to-refresh sends Apple Health to the hub FIRST (like opening the
    /// app does), so a pull right after waking brings last night in. Set by the app shell; nil in
    /// previews/tests → refresh only reloads.
    @ObservationIgnored public var uploadBeforeRefresh: (@MainActor () async -> Void)?

    public func refresh() async {
        await uploadBeforeRefresh?()
        await TodayWorkoutsModel.shared.refresh()
        await fetchLive()
    }

    /// B-107: re-fetch the hub's `/morning` + `/gate` (and the other live sections) now, without the
    /// Health upload `refresh()` does first — Settings' "I'm on a break" toggle calls this so Decide's
    /// Load row reads "Paused" (and the gate drops the ACWR verdict, B-110) without a relaunch.
    public func reloadLive() async {
        await fetchLive()
    }

    private func restoreFromCache() {
        if let m = try? cache.get(Self.keys.morning, as: MorningResponse.self) {
            morning = m.value; fetchedAt = m.fetchedAt; morningFetchedAt = m.fetchedAt; everSynced = true
        }
        if let g = try? cache.get(Self.keys.gate, as: GateResponse.self) { gate = g.value; gateFetchedAt = g.fetchedAt }
        fuelHealth.restore(from: cache)   // W-FIX7 N-1: last launch's Health food until this launch's read lands
        if let r = try? cache.get(Self.keys.recovery, as: [RecoveryDay].self) { recovery = KpiMetrics.honestRecovery(r.value); recoveryFetchedAt = r.fetchedAt }
        if let s = try? cache.get(Self.keys.sleepSummary, as: SleepSummary.self) { sleepSummary = s.value }
        if let n = try? cache.get(Self.keys.lastNight, as: RecoveryLastNight.self) { lastNightReport = n.value }
        if let e = try? cache.get(Self.keys.exercises, as: [Exercise].self) { exercises = e.value }
        if let p = try? cache.get(Self.keys.planSessions, as: [PlanSessionOut].self) { planSessions = p.value }
        if let w = try? cache.get(Self.keys.planWeek, as: PlanWeekOut.self), w.value.start == planWeekStart(todayDateString) {
            planWeek = w.value
        }
        if let v = try? cache.get(Self.keys.verdictReason, as: MorningVerdict.self), v.value.date == morning?.verdictDate {
            verdictReason = v.value.reason
        }
        // W-FIX11 H1-15 (+H2-05): the hub's last sync survives an offline relaunch (never "Not synced yet").
        if let h = try? cache.get(Self.keys.hubLastSync, as: Date.self) { hubLastSync = h.value }
        lastUploadAt = readLastUpload()
        if morning != nil { phase = .loaded }
        syncMorningState()
        if morning != nil || gate != nil || !recovery.isEmpty { onSectionUpdate?() }
    }

    /// W-B57-W3 fixer: Trends' 28-day normal spans today−34 … today−7 (`PersonalNormal`), so Today
    /// fetches 42 days (the plan's window). The hub's `avg_*_7d` stay the last 7 days whatever this is.
    public nonisolated static let trendWindowDays = 42

    private func fetchLive() async {
        let hadEverSynced = everSynced
        do {
            // PARITY-7: each section fetched (and cache-fallen-back) independently via `SectionLoader` —
            // one section's failure no longer fails the others, unlike the old single `try await` batch.
            // Local copies of `provider`/`cache` (both Sendable) so the `async let` closures below don't
            // need to capture `self` (MainActor-isolated) across the child-task boundary they create.
            let provider = self.provider
            let cache = self.cache
            // W-FIX6 F6-11: the call is the hub's; the gate rows too when the data source has none.
            let verdictSource = self.verdictProvider
            let gateSource = provider.capabilities.contains(.gate) ? provider : verdictSource
            async let mR = SectionLoader.load(key: Self.keys.morning, cache: cache) { try await verdictSource.morning() }
            async let gR = SectionLoader.load(key: Self.keys.gate, cache: cache) { try await gateSource.gate(windowDays: Self.trendWindowDays) }
            async let rR = SectionLoader.load(key: Self.keys.recovery, cache: cache) { try await provider.recovery(windowDays: Self.trendWindowDays) }
            // W-FIX2 L5: the sleep summary and the hub's sync time are extras — they never drive
            // `phase`/`hubReachable`, and a failure keeps the last known value.
            async let sR = Self.loadSleepSummary(provider: provider, cache: cache)
            async let lnR = Self.loadLastNight(provider: provider, cache: cache)
            async let hR = Self.loadHubLastSync(provider: provider)
            async let eR = Self.loadExercises(provider: provider, cache: cache)
            let today = todayDateString
            async let wR = Self.loadHubWorkouts(provider: provider, cache: cache, date: today)
            async let pR = Self.loadPlanSessions(provider: provider, cache: cache)
            async let pwR = Self.loadPlanWeek(provider: provider, cache: cache, date: today)
            let (m, g, r) = try await (mR, gR, rR)
            if let pv = await pR { planSessions = pv }
            planWeek = await pwR   // nil when not served: never keep another week's answer
            if let sv = await sR { sleepSummary = sv }
            if let ln = await lnR { lastNightReport = ln }   // answered: even nil replaces (no stale night)
            if let hv = await hR { hubLastSync = hv; try? cache.put(Self.keys.hubLastSync, hv) }
            if let ev = await eR { exercises = ev }
            if let wv = await wR { hubDay = wv }
            lastUploadAt = readLastUpload()

            if let mv = m.value { morning = mv; syncMorningState() }
            // W-FIX10 R-05: the call's persisted reason (the held "Waiting for the watch…" line).
            if let date = morning?.verdictDate {
                verdictReason = await Self.loadVerdictReason(provider: verdictSource, cache: cache, date: date)
            }
            if let gv = g.value { gate = gv }
            // W-FIX1 BUG-12: the hub's invented `acwr` 0.0 is cleared here, so every Day reader of the
            // rows (the hero Load ring, the EditToday square, Trends) shows "—", never "0.00".
            if let rv = r.value { recovery = KpiMetrics.honestRecovery(rv) }
            morningFetchedAt = m.fetchedAt ?? morningFetchedAt
            gateFetchedAt = g.fetchedAt ?? gateFetchedAt
            recoveryFetchedAt = r.fetchedAt ?? recoveryFetchedAt
            fetchedAt = morningFetchedAt

            // Pick one representative error to drive `phase`/`hubReachable`: unauthorized (a token
            // problem) always wins so it's never masked by a sibling section's network error; network
            // wins over any other typed error so "hub unreachable" isn't hidden behind e.g. a decode
            // failure elsewhere. PARITY-3's typed-error branching carries over unchanged, just fed from
            // the merged per-section errors instead of a single batch exception.
            let sectionErrors = [m.error, g.error, r.error].compactMap { $0 }
            let representative = sectionErrors.first { if case .unauthorized = $0 { return true }; return false }
                ?? sectionErrors.first { if case .network = $0 { return true }; return false }
                ?? sectionErrors.first
            lastError = representative

            switch representative {
            case .some(.unauthorized):
                hubReachable = true
                phase = .error(Self.describe(representative!))
            case .some(.network):
                hubReachable = false
                phase = (morning == nil) ? .error(Self.describe(representative!)) : .loaded
            case .some(let e):
                hubReachable = true
                phase = (morning == nil) ? .error(Self.describe(e)) : .loaded
            case .none:
                hubReachable = true
                hasLiveResult = true
                everSynced = true
                let isEmpty = (morning?.verdict == nil && recovery.isEmpty)
                neverSyncedObserved = isEmpty && !hadEverSynced
                phase = isEmpty ? .empty : .loaded
            }
            onSectionUpdate?()
        } catch {
            // A tab switch cancels the view's `.task`; that is not a hub outage. Return to `.idle`
            // so `TodayView.task` reloads on the next appearance instead of showing a false error.
            // `hasLiveResult` stays false either way — CODE-1: a cancelled fetch over a WARM cache
            // leaves `phase == .loaded` (from `restoreFromCache`), not `.idle`, so the view's reload
            // trigger must key off `hasLiveResult`, not `phase`. `SectionLoader` only ever rethrows on
            // cancellation (see its doc comment), so this branch is reached solely by that path in
            // practice; the non-cancellation fallback below matches the old catch-all shape defensively.
            if Task.isCancelled { if phase == .loading { phase = .idle }; return }
            lastError = (error as? HubError) ?? .decoding("\(error)")
            hubReachable = true
            phase = (morning == nil) ? .error(Self.describe(error)) : .loaded
            onSectionUpdate?()
        }
    }

    private func readLastUpload() -> Date? { parseHubTimestamp(uploadRecord?.string(forKey: Self.lastUploadKey)) }

    nonisolated private static func loadSleepSummary(provider: any HealthDataProvider, cache: OfflineCache) async -> SleepSummary? {
        guard let sp = provider as? any SleepSummaryProviding else { return nil }
        return (try? await SectionLoader.load(key: keys.sleepSummary, cache: cache) { try await sp.sleepSummary() })?.value
    }

    /// F-7: `.some(night)` when the hub answered (night may be nil), nil when not served / failed
    /// (the last known night stays).
    /// (A cached night older than 36 h is never shown — `lastNightReading` checks freshness.)
    nonisolated private static func loadLastNight(provider: any HealthDataProvider, cache: OfflineCache) async -> RecoveryLastNight?? {
        guard let lp = provider as? any RecoveryLastNightProviding else { return nil }
        do {
            let night = try await lp.recoveryLastNight()
            if let night { try? cache.put(lastNightCacheKey, night) }
            return .some(night)
        } catch { return nil }
    }

    nonisolated private static func loadExercises(provider: any HealthDataProvider, cache: OfflineCache) async -> [Exercise]? {
        guard let tp = provider as? any TrainingProviding else { return nil }
        return (try? await SectionLoader.load(key: keys.exercises, cache: cache) { try await tp.exercises() })?.value
    }

    nonisolated private static func loadPlanSessions(provider: any HealthDataProvider, cache: OfflineCache) async -> [PlanSessionOut]? {
        guard let tp = provider as? any TrainingProviding else { return nil }
        return (try? await SectionLoader.load(key: keys.planSessions, cache: cache) { try await tp.planSessions() })?.value
    }

    /// W-SSOT-1 SS-7: `date`'s week from the hub; nil when the route is not served (the rows answer).
    nonisolated private static func loadPlanWeek(provider: any HealthDataProvider, cache: OfflineCache, date: String) async -> PlanWeekOut? {
        guard let tp = provider as? any TrainingProviding, let start = planWeekStart(date) else { return nil }
        let week = (try? await SectionLoader.load(key: keys.planWeek, cache: cache) { try await tp.planWeek(start: start) })?.value
        return week?.start == start ? week : nil   // a cached fallback from another week is no answer
    }

    /// The reason of `date`'s call; nil when the hub has none for that date (never another day's).
    nonisolated private static func loadVerdictReason(provider: any HealthDataProvider, cache: OfflineCache, date: String) async -> String? {
        let row = (try? await SectionLoader.load(key: keys.verdictReason, cache: cache) { try await provider.morningVerdict(date: date) })?.value
        guard let row, row.date == date else { return nil }
        return row.reason
    }

    nonisolated private static func loadHubWorkouts(provider: any HealthDataProvider, cache: OfflineCache, date: String) async -> TrainingDayDetail? {
        guard let tp = provider as? any TrainingProviding else { return nil }
        return (try? await SectionLoader.load(key: "training.day.\(date)", cache: cache) { try await tp.trainingDay(date: date) })?.value
    }

    nonisolated private static func loadHubLastSync(provider: any HealthDataProvider) async -> Date? {
        parseHubTimestamp((try? await provider.syncStatus())?.lastSync)
    }

    /// Reduces `event` into `morningState` and persists it under the current verdict date.
    public func morningEvent(_ event: TodayMorningEvent) {
        morningState = TodayMorningFlow.next(morningState, event)
        guard let date = verdictDate else { return }
        memoryMorningStates[date] = morningState
        try? prefs?.set(TodayMorningFlow.prefKey(verdictDate: date), morningState)
    }

    /// Re-reads the reached state whenever the verdict date changes (§2: kept per verdict date).
    private func syncMorningState() {
        guard let date = verdictDate else { morningState = .decide; syncedVerdictDate = nil; return }
        guard date != syncedVerdictDate else { return }
        syncedVerdictDate = date
        let stored = (try? prefs?.get(TodayMorningFlow.prefKey(verdictDate: date), as: TodayMorningState.self)) ?? nil
        morningState = stored ?? memoryMorningStates[date] ?? .decide
    }

#if DEBUG
    /// Test seam: assigns `morning` the way a fetch would, then re-syncs the morning state.
    func setMorningForTesting(_ m: MorningResponse) { morning = m; syncMorningState() }
#endif

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}

// MARK: - B-33 §8.5 fixture

public extension TodayViewModel {
    /// A loaded Today, built from wire-format literals (the DTOs' memberwise inits are internal),
    /// for `ScreenRegistry`/the screenshot sweep. Never used by the app.
    /// `nil` only when an in-memory SQLite file cannot be opened — the registry then renders the
    /// screen's unavailable state rather than trapping inside a test run.
    static func fixture() -> TodayViewModel? { fixture(morningState: .day) }

    /// B-57: the same loaded Today pinned to one morning state (Decide / Coach / Day) for the
    /// gallery. Fixtures never persist — the state is set directly.
    static func fixture(morningState: TodayMorningState, morningJSON: String? = nil) -> TodayViewModel? {
        guard let cache = NativeFixtureStore.cache else { return nil }
        // Pinned to the fixture's verdict day so its nights read as last night (BUG-05 freshness).
        let model = TodayViewModel(provider: MockDataProvider(), cache: cache, now: { Date(timeIntervalSince1970: 1_789_992_000) })
        model.morning = NativeFixtureStore.decode(morningJSON ?? fixtureMorningJSON, as: MorningResponse.self)
        model.gate = NativeFixtureStore.decode(fixtureGateJSON, as: GateResponse.self)
        model.recovery = (0..<7).map { i in
            RecoveryDay(
                date: "2026-09-\(15 + i)",
                sleepScore: [78, 81, 74, 88, 83, 79, 85][i],
                sleepDurationSec: [25_200, 26_400, 23_400, 28_200, 27_000, 25_800, 27_600][i],
                rhrBpm: [54, 53, 55, 52, 53, 54, 52][i],
                bodyBatteryAvg: [61, 64, 58, 70, 66, 62, 68][i],
                readinessScore: [68, 71, 64, 79, 74, 70, 76][i],
                acwr: [1.02, 1.05, 1.11, 0.97, 1.01, 1.08, 1.04][i],
                hrvWeeklyAvg: [48, 50, 47, 53, 51, 49, 52][i]
            )
        }
        model.fetchedAt = Date(timeIntervalSince1970: 1_789_992_000)
        model.phase = .loaded
        model.hasLiveResult = true
        model.morningState = morningState
        return model
    }
}

/// W-FIX6 F6-11: the prod hub's `GET /api/v1/planning/morning` on 2026-09-28 after morning_go
/// 05:27 (saved read-only) — the call Decide, the widget and the Live Activity must all show.
nonisolated public let fix6Morning20260928JSON = """
{"today_activities":[],"verdict":"GO (auto-regulated) — Day 1 Full Upper + Z2 40min","verdict_date":"2026-09-28","experiment":null,"carbs_3d_avg":null,"carb_watch_floor":120,
 "hrv_series":[{"date":"2026-09-22","hrv_weekly_avg":34,"rhr_bpm":79},{"date":"2026-09-23","hrv_weekly_avg":35,"rhr_bpm":67},{"date":"2026-09-24","hrv_weekly_avg":30,"rhr_bpm":82},{"date":"2026-09-25","hrv_weekly_avg":25,"rhr_bpm":80},{"date":"2026-09-26","hrv_weekly_avg":34,"rhr_bpm":73},{"date":"2026-09-27","hrv_weekly_avg":34,"rhr_bpm":70},{"date":"2026-09-28","hrv_weekly_avg":32,"rhr_bpm":71}],
 "hrv_rmssd_series":[{"date":"2026-09-22","hrv_rmssd_ms":25.0},{"date":"2026-09-23","hrv_rmssd_ms":24.78},{"date":"2026-09-24","hrv_rmssd_ms":20.71},{"date":"2026-09-25","hrv_rmssd_ms":20.68},{"date":"2026-09-26","hrv_rmssd_ms":24.21},{"date":"2026-09-27","hrv_rmssd_ms":23.72},{"date":"2026-09-28","hrv_rmssd_ms":20.5}],
 "is_stale":false,"session_for_today":null,
 "gate_signals":[
  {"key":"hrv","label":"HRV (7-day)","value":23,"unit":"ms","threshold":25,"direction":"min","scale_min":0,"scale_max":120,"status":"amber","note":"HRV 20 ms — 2 nights falling below 25 ms"},
  {"key":"sleep_h","label":"Sleep time","value":8.2,"unit":"h","threshold":7.0,"direction":"min","scale_min":0,"scale_max":10,"status":"context","note":"8.2 h sleep — above your 7 h goal"},
  {"key":"hrv_day","label":"Daytime HRV","value":14.08,"unit":"ms","threshold":21.0,"direction":"min","scale_min":0,"scale_max":120,"status":"context","note":"daytime HRV 14.08 ms vs 21 (undosed weekends) — context only"},
  {"key":"recovery","label":"Recovery score","value":36,"unit":"","threshold":35,"direction":"min","scale_min":0,"scale_max":100,"status":"pass","note":"Recovery 36"}],
 "verdict_override":null}
"""

let fixtureMorningJSON = """
{"today_activities":[],"verdict":"MODIFIED (HRV low) — Easy Z2 30–40 min","verdict_date":"2026-09-21","carb_watch_floor":180,"carbs_3d_avg":214,
 "session_for_today":"Full Upper","verdict_computed_at":"2026-09-21T05:10:00+02:00",
 "strain":{"status":"ok","loaded_days":43,"min_loaded_days":19,"window_days":120,"ceiling":6.03,"usual_low":30,"usual_high":55,
  "yesterday":{"date":"2026-09-20","value":47,"sessions":[{"name":"Outdoor Run","minutes":48}]},"today":{"date":"2026-09-21","value":12}},
 "gate_signals":[
  {"key":"sleep","label":"Sleep","value":81,"unit":"","threshold":70,"direction":"min","scale_min":0,"scale_max":100,"status":"pass","note":null},
  {"key":"hrv","label":"HRV","value":24,"unit":"ms","threshold":27,"direction":"min","scale_min":0,"scale_max":80,"status":"amber","note":"hrv 24 — under 27"},
  {"key":"rhr","label":"RHR","value":52,"unit":"bpm","threshold":65,"direction":"max","scale_min":40,"scale_max":80,"status":"pass","note":null},
  {"key":"sleep_h","label":"Sleep time","value":7.3,"unit":"h","threshold":6.0,"direction":"min","scale_min":0,"scale_max":10,"status":"pass","note":null}],
 "hrv_series":[{"date":"2026-09-15","hrv_weekly_avg":48,"rhr_bpm":54},{"date":"2026-09-16","hrv_weekly_avg":50,"rhr_bpm":53},
 {"date":"2026-09-17","hrv_weekly_avg":47,"rhr_bpm":55},{"date":"2026-09-18","hrv_weekly_avg":53,"rhr_bpm":52},
 {"date":"2026-09-19","hrv_weekly_avg":51,"rhr_bpm":53},{"date":"2026-09-20","hrv_weekly_avg":49,"rhr_bpm":54},
 {"date":"2026-09-21","hrv_weekly_avg":52,"rhr_bpm":52}]}
"""

/// W-DECIDE-HYBRID H-4: the same morning after the call (Go saved) — the Strain card's after state.
let fixtureMorningAfterCallJSON = fixtureMorningJSON.replacingOccurrences(
    of: "\"session_for_today\":\"Full Upper\",",
    with: "\"session_for_today\":\"Full Upper\",\"verdict_override\":{\"date\":\"2026-09-21\",\"choice\":\"accept\",\"reason\":null,\"session\":\"Easy Z2 30–40 min\",\"created_at\":\"2026-09-21T07:45:00+02:00\"},")

/// B-65: an Apple Watch night — the hub's three Apple arcs (`hrv` 7-day band, `sleep_h` floor —
/// the user's own; this fixture's night was judged against 7.0 h —
/// `hrv_day` context) in place of the Garmin four.
let fixtureMorningAppleJSON = """
{"today_activities":[],"verdict":"MODIFIED (sleep < 7 h) — Easy Z2 30–40 min","verdict_date":"2026-09-23","carb_watch_floor":180,"carbs_3d_avg":214,
 "session_for_today":"Full Upper",
 "gate_signals":[
  {"key":"hrv","label":"HRV (7-day)","value":46,"unit":"ms","threshold":41,"direction":"min","scale_min":0,"scale_max":80,"status":"pass","note":"band 41–52 ms"},
  {"key":"sleep_h","label":"Sleep time","value":6.6,"unit":"h","threshold":7.0,"direction":"min","scale_min":0,"scale_max":10,"status":"amber","note":"6.6 h — under 7.0"},
  {"key":"hrv_day","label":"HRV (day)","value":31,"unit":"ms","threshold":0,"direction":"min","scale_min":0,"scale_max":80,"status":"context","note":"weekday — dosed"}],
 "hrv_series":[]}
"""

let fixtureGateJSON = """
{"averages":{"avg_kcal_7d":2410,"avg_protein_7d":158,"avg_weight_kg":96.4,"avg_rhr_bpm":53,"sleep_score_7d":81,"acwr":1.04,"trends":{"weight":"down","kcal":"flat"}},
 "daily":[{"date":"2026-09-15","steps":8120,"kcal_consumed":2380,"protein_g":151},{"date":"2026-09-16","steps":10450,"kcal_consumed":2440,"protein_g":163},
 {"date":"2026-09-17","steps":6980,"kcal_consumed":2290,"protein_g":147},{"date":"2026-09-18","steps":11230,"kcal_consumed":2510,"protein_g":166},
 {"date":"2026-09-19","steps":9040,"kcal_consumed":2400,"protein_g":159},{"date":"2026-09-20","steps":7610,"kcal_consumed":2350,"protein_g":154},
 {"date":"2026-09-21","steps":6420,"kcal_consumed":2470,"protein_g":161}],
 "recommendation":"MAINTAIN","tracked_days":7,"total_days":7,"min_tracked_days":5,
 "triggered_rules":["acwr_in_band","protein_on_target"],"suggestions":["Hold the current intake for another week."]}
"""

/// W-FIX2 L5 (DEV-03): the hub's `last_sync` ("2026-09-25 10:02:23.725876+02:00", Postgres text)
/// or the uploader's ISO-8601 instant, as a `Date`; `nil` for a missing or unreadable value.
nonisolated func parseHubTimestamp(_ raw: String?) -> Date? {
    guard var text = raw?.trimmingCharacters(in: .whitespaces), text.count >= 19 else { return nil }
    if text.count > 10, text[text.index(text.startIndex, offsetBy: 10)] == " " {
        text.replaceSubrange(text.index(text.startIndex, offsetBy: 10)...text.index(text.startIndex, offsetBy: 10), with: "T")
    }
    // Postgres may send more than millisecond precision; the formatter reads at most three digits.
    if let dot = text.firstIndex(of: "."), let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
        let digits = text[text.index(after: dot)..<end]
        if digits.count > 3 { text.replaceSubrange(text.index(after: dot)..<end, with: digits.prefix(3)) }
    }
    let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return frac.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

// MARK: - W-FIX7 F7-1 (S1): today's workouts from Apple Health

/// Today's Apple Health workouts, read on the phone (no hub path — Toby 2026-09-28). ONE shared
/// model so Decide, Day, Training and the glances agree: the App installs `source` (JIHealthKit's
/// `HKTodayWorkoutsReader`) and `onChange` (republish the widgets / Live Activity); screens read
/// `completion(sessionLabel:)` and `TrainingWeekSummary.applyingTodayWorkouts`.
/// No source (tests, previews, `-no-healthkit`) = no workouts = every session as it was.
@Observable @MainActor
public final class TodayWorkoutsModel {
    public static let shared = TodayWorkoutsModel()

    @ObservationIgnored public var source: (any TodayWorkoutsProviding)?
    /// Fired on the first successful read and when a refresh changed the rows (never on an unchanged re-read).
    @ObservationIgnored public var onChange: (() -> Void)?
    private var rows: [TodayWorkout] = []
    /// W-FIX7 fixer F7-4: true once a read from `source` succeeded this launch.
    private var hasRead = false
    private let now: () -> Date
    private let calendar: Calendar

    public init(source: (any TodayWorkoutsProviding)? = nil, now: @escaping () -> Date = Date.init,
                calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()) {
        self.source = source; self.now = now; self.calendar = calendar
    }

    /// The rows read, minus any that started before today (a read from yesterday evening never
    /// marks this morning's session done).
    public var workouts: [TodayWorkout] {
        let today = now()
        return rows.filter { calendar.isDate($0.start, inSameDayAs: today) }
    }

    /// W-FIX7 fixer F7-4: whether "done" is known yet — no source (tests, `-no-healthkit`), or the
    /// first read landed. The Live Activity waits for it: a launch that drove the activity before
    /// Health answered requested a fresh card, then ended it as "done" — one more card per relaunch.
    public var isSettled: Bool { source == nil || hasRead }
    /// W-FIX7: a Health workouts read succeeded this launch (Settings › Apple Health "Workouts" row).
    public var hasReadHealth: Bool { hasRead }

    /// Re-reads Health. A failed read keeps the last rows (never flips a done session back).
    public func refresh() async {
        guard let source, let fresh = try? await source.todayWorkouts() else { return }
        let first = !hasRead
        hasRead = true
        // The first read always fires (it settles "done" for the Live Activity), later ones on change.
        guard fresh != rows || first else { return }
        rows = fresh
        onChange?()
    }

    /// Today's session (by its label — "Day 1 Full Upper", "Long Z2", "Rest") against today's
    /// workouts: Apple Health's, plus the hub's `core.activity` rows (`hub`, Garmin + Apple — W-FIX9 G1).
    /// W-SSOT-1 SS-2: `hubCompletion` (the hub's `/training/day` `completion`) is preferred when present.
    public func completion(sessionLabel: String?, hub: [DayActivity] = [], hubCompletion: HubCompletion? = nil) -> SessionCompletion {
        progress(sessionLabel: sessionLabel, hub: hub, hubCompletion: hubCompletion).completion
    }

    /// W-FIX9 G5: every part of today's session (the same rule as `completion`).
    public func progress(sessionLabel: String?, hub: [DayActivity] = [], hubCompletion: HubCompletion? = nil) -> SessionProgress {
        SessionCompletion.progress(sessionLabel: sessionLabel, workouts: TodayWorkout.merging(local: workouts, hub: hub),
                                   hub: hubCompletion)
    }
}

public extension TodayViewModel {
    /// F7-1: the label of today's planned session — the hub's session for today, else (W-FIX10 R-01)
    /// the plan's session for today's weekday, else the call's session.
    var plannedSessionLabel: String? {
        [morning?.sessionForToday, scheduledSessionToday, verdict.session].compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// F7-1: today's session against today's workouts — Apple Health and the hub (W-FIX9 G1).
    /// `.none` = unchanged.
    func sessionCompletion(workouts: TodayWorkoutsModel = .shared, sessionLabel: String? = nil) -> SessionCompletion {
        workouts.completion(sessionLabel: sessionLabel ?? plannedSessionLabel, hub: hubWorkouts,
                            hubCompletion: sessionLabel == nil ? hubDay?.completion : nil)
    }

    /// W-FIX9 C-1: the parts of today's session, for the summary line (same rule, same inputs).
    func sessionProgress(workouts: TodayWorkoutsModel = .shared, sessionLabel: String? = nil) -> SessionProgress {
        workouts.progress(sessionLabel: sessionLabel ?? plannedSessionLabel, hub: hubWorkouts,
                          hubCompletion: sessionLabel == nil ? hubDay?.completion : nil)
    }
}

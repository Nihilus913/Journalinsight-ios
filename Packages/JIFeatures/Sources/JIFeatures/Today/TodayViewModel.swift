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
    public private(set) var gate: GateResponse?
    public private(set) var recovery: [RecoveryDay] = []
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
    private let cache: OfflineCache
    /// Optional — nil at call sites that haven't wired tile-order persistence yet (e.g. pre-W2b
    /// `RootTabView`). `TodayGrid` degrades gracefully to an unpersisted default order when nil.
    private let prefs: PrefStore?
    private let now: () -> Date
    private static let keys = (morning: "today.morning", gate: "today.gate", recovery: "today.recovery", sleepSummary: "today.sleepSummary")

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
    private static let lastUploadKey = "hk.upload.lastSuccess"

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
    public init(provider: any HealthDataProvider, cache: OfflineCache, prefs: PrefStore? = nil, now: @escaping () -> Date = Date.init,
                uploadRecord: UserDefaults? = UserDefaults(suiteName: "group.toby913.JournalInsight")) {
        self.provider = provider; self.cache = cache; self.prefs = prefs; self.now = now; self.uploadRecord = uploadRecord
    }

    /// The `PrefStore` `TodayGrid` persists its drag-reorder tile order to (`today.tileOrder`).
    /// `nil` at call sites that haven't wired it yet — see `prefs`'s doc comment.
    public var tileOrderStore: PrefStore? { prefs }

    /// DESIGN-7 screen state — a pure refinement of `phase` (see `ScreenState.resolve`); read this for
    /// never-synced / stale-verdict-date / yazioAuthExpired copy instead of re-deriving them from `phase`.
    public var screenState: ScreenState {
        ScreenState.resolve(phase: phase, neverSynced: neverSyncedObserved, verdictDate: morning?.verdictDate, todayDateString: todayDateString, lastError: lastError)
    }

    private var todayDateString: String { String(now().ISO8601Format().prefix(10)) }

    public var verdict: VerdictParts { verdictParts(morning?.verdict) }

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

    public var readiness: Double? { lastNight(\.readinessScore)?.value }

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
                 latest: lastNight { KpiMetrics.nightlyHrvMs($0) }),
            chip("rhr", "RHR", unit: "bpm", points: rec.map(\.rhrBpm), sourceMissing: false,
                 latest: lastNight(\.rhrBpm)),
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
        ]
    }

    /// W-FIX2 fixer BUG-19: what Today's `TodayGrid` is handed — every EditToday square (the grid
    /// then filters/orders them by EditToday's prefs), so EditToday's 8 of 8 = Today's 8 tiles.
    public var gridChips: [TodayChip] { squareChips }

    public func load() async {
        phase = .loading
        restoreFromCache()
        await fetchLive()
    }

    public func refresh() async { await fetchLive() }

    private func restoreFromCache() {
        if let m = try? cache.get(Self.keys.morning, as: MorningResponse.self) {
            morning = m.value; fetchedAt = m.fetchedAt; morningFetchedAt = m.fetchedAt; everSynced = true
        }
        if let g = try? cache.get(Self.keys.gate, as: GateResponse.self) { gate = g.value; gateFetchedAt = g.fetchedAt }
        if let r = try? cache.get(Self.keys.recovery, as: [RecoveryDay].self) { recovery = KpiMetrics.honestRecovery(r.value); recoveryFetchedAt = r.fetchedAt }
        if let s = try? cache.get(Self.keys.sleepSummary, as: SleepSummary.self) { sleepSummary = s.value }
        lastUploadAt = readLastUpload()
        if morning != nil { phase = .loaded }
        syncMorningState()
        if morning != nil || gate != nil || !recovery.isEmpty { onSectionUpdate?() }
    }

    private func fetchLive() async {
        let hadEverSynced = everSynced
        do {
            // PARITY-7: each section fetched (and cache-fallen-back) independently via `SectionLoader` —
            // one section's failure no longer fails the others, unlike the old single `try await` batch.
            // Local copies of `provider`/`cache` (both Sendable) so the `async let` closures below don't
            // need to capture `self` (MainActor-isolated) across the child-task boundary they create.
            let provider = self.provider
            let cache = self.cache
            async let mR = SectionLoader.load(key: Self.keys.morning, cache: cache) { try await provider.morning() }
            async let gR = SectionLoader.load(key: Self.keys.gate, cache: cache) { try await provider.gate(windowDays: 28) }
            async let rR = SectionLoader.load(key: Self.keys.recovery, cache: cache) { try await provider.recovery(windowDays: 28) }
            // W-FIX2 L5: the sleep summary and the hub's sync time are extras — they never drive
            // `phase`/`hubReachable`, and a failure keeps the last known value.
            async let sR = Self.loadSleepSummary(provider: provider, cache: cache)
            async let hR = Self.loadHubLastSync(provider: provider)
            let (m, g, r) = try await (mR, gR, rR)
            if let sv = await sR { sleepSummary = sv }
            if let hv = await hR { hubLastSync = hv }
            lastUploadAt = readLastUpload()

            if let mv = m.value { morning = mv; syncMorningState() }
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

    /// Test seam: assigns `morning` the way a fetch would, then re-syncs the morning state.
    func setMorningForTesting(_ m: MorningResponse) { morning = m; syncMorningState() }

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

let fixtureMorningJSON = """
{"today_activities":[],"verdict":"MODIFIED (HRV low) — Easy Z2 30–40 min","verdict_date":"2026-09-21","carb_watch_floor":180,"carbs_3d_avg":214,
 "session_for_today":"Full Upper",
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

/// B-65: an Apple Watch night — the hub's three Apple arcs (`hrv` 7-day band, `sleep_h` 7 h floor,
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

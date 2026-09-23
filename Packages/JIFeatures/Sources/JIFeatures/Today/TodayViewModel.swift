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
    private static let keys = (morning: "today.morning", gate: "today.gate", recovery: "today.recovery")
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

    public init(provider: any HealthDataProvider, cache: OfflineCache, prefs: PrefStore? = nil, now: @escaping () -> Date = Date.init) {
        self.provider = provider; self.cache = cache; self.prefs = prefs; self.now = now
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

    /// Newest row (by `date`, ascending sort) whose `value` isn't nil — mirrors RN VerdictHero.tsx's
    /// "newest non-null value per metric" resolution, as opposed to picking a single newest ROW and
    /// reading every field off it (a null field on the newest row would otherwise blank every metric).
    private func newestNonNullValue<T>(_ rows: [T], date: (T) -> String, value: (T) -> Double?) -> Double? {
        newestNonNull(rows, date: date, value: value)?.value
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

    public var readiness: Double? { newestNonNullValue(recovery, date: \.date, value: \.readinessScore) }

    public var chips: [TodayChip] {
        let caps = provider.capabilities
        let hrvSeries = morning?.hrvSeries ?? []
        let chron = hrvSeries.sorted { $0.date < $1.date }.suffix(7)
        let rec = recovery.sorted { $0.date < $1.date }.suffix(7)
        let daily = gate?.daily ?? []
        // PARITY-1: steps mirrors RN VerdictHero.tsx:312-323 — newest non-null `values["steps"]` over
        // date-sorted `gate.daily`. `resolveTodayRow` stays reserved for the future W2 kcal/protein
        // ring: it skips null-food rows on purpose, which lands on the wrong date for steps.
        let steps = newestNonNull(daily, date: \.date, value: { $0.values["steps"] ?? nil })
        return [
            chip("hrv", "HRV", unit: "ms", points: chron.map(\.hrvWeeklyAvg), sourceMissing: !caps.contains(.hrvRMSSD),
                 latest: newestNonNull(hrvSeries, date: \.date, value: \.hrvWeeklyAvg)),
            chip("rhr", "RHR", unit: "bpm", points: rec.map(\.rhrBpm), sourceMissing: false,
                 latest: newestNonNull(recovery, date: \.date, value: \.rhrBpm)),
            chip("sleep", "Sleep", unit: nil, points: rec.map(\.sleepScore), sourceMissing: !caps.contains(.garminSleepScore),
                 latest: newestNonNull(recovery, date: \.date, value: \.sleepScore)),
            chip("steps", "Steps", unit: nil, points: daily.sorted { $0.date < $1.date }.suffix(7).map { $0.values["steps"] ?? nil }, sourceMissing: false,
                 latest: steps),
        ]
    }

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
        if let r = try? cache.get(Self.keys.recovery, as: [RecoveryDay].self) { recovery = r.value; recoveryFetchedAt = r.fetchedAt }
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
            let (m, g, r) = try await (mR, gR, rR)

            if let mv = m.value { morning = mv; syncMorningState() }
            if let gv = g.value { gate = gv }
            if let rv = r.value { recovery = rv }
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
    static func fixture(morningState: TodayMorningState) -> TodayViewModel? {
        guard let cache = NativeFixtureStore.cache else { return nil }
        let model = TodayViewModel(provider: MockDataProvider(), cache: cache)
        model.morning = NativeFixtureStore.decode(fixtureMorningJSON, as: MorningResponse.self)
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

let fixtureGateJSON = """
{"averages":{"avg_kcal_7d":2410,"avg_protein_7d":158,"avg_weight_kg":96.4,"avg_rhr_bpm":53,"sleep_score_7d":81,"acwr":1.04,"trends":{"weight":"down","kcal":"flat"}},
 "daily":[{"date":"2026-09-15","steps":8120,"kcal_consumed":2380,"protein_g":151},{"date":"2026-09-16","steps":10450,"kcal_consumed":2440,"protein_g":163},
 {"date":"2026-09-17","steps":6980,"kcal_consumed":2290,"protein_g":147},{"date":"2026-09-18","steps":11230,"kcal_consumed":2510,"protein_g":166},
 {"date":"2026-09-19","steps":9040,"kcal_consumed":2400,"protein_g":159},{"date":"2026-09-20","steps":7610,"kcal_consumed":2350,"protein_g":154},
 {"date":"2026-09-21","steps":6420,"kcal_consumed":2470,"protein_g":161}],
 "recommendation":"MAINTAIN","tracked_days":7,"total_days":7,"min_tracked_days":5,
 "triggered_rules":["acwr_in_band","protein_on_target"],"suggestions":["Hold the current intake for another week."]}
"""

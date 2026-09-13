import Foundation
import Observation
import JICore
import JIPersistence

nonisolated public struct TodayChip: Identifiable, Equatable, Sendable {
    public let id: String, label: String, value: Double?, unit: String?, points: [Double?], sourceMissing: Bool
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
    private let now: () -> Date
    private static let keys = (morning: "today.morning", gate: "today.gate", recovery: "today.recovery")
    /// Whether ANY section has ever synced successfully — set once from a warm cache at `restoreFromCache`,
    /// or the first time a live fetch fully succeeds — and never cleared by a later failure. Distinguishes
    /// a truly first-ever empty response (`.neverSynced`) from an established screen going transiently
    /// blank (`.empty`).
    private var everSynced = false
    private var neverSyncedObserved = false

    public init(provider: any HealthDataProvider, cache: OfflineCache, now: @escaping () -> Date = Date.init) {
        self.provider = provider; self.cache = cache; self.now = now
    }

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
        for row in rows.sorted(by: { date($0) > date($1) }) {
            if let v = value(row) { return v }
        }
        return nil
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
        let steps = newestNonNullValue(daily, date: \.date, value: { $0.values["steps"] ?? nil })
        return [
            TodayChip(id: "hrv", label: "HRV", value: newestNonNullValue(hrvSeries, date: \.date, value: \.hrvWeeklyAvg), unit: "ms", points: chron.map(\.hrvWeeklyAvg), sourceMissing: !caps.contains(.hrvRMSSD)),
            TodayChip(id: "rhr", label: "RHR", value: newestNonNullValue(recovery, date: \.date, value: \.rhrBpm), unit: "bpm", points: rec.map(\.rhrBpm), sourceMissing: false),
            TodayChip(id: "sleep", label: "Sleep", value: newestNonNullValue(recovery, date: \.date, value: \.sleepScore), unit: nil, points: rec.map(\.sleepScore), sourceMissing: !caps.contains(.garminSleepScore)),
            TodayChip(id: "steps", label: "Steps", value: steps, unit: nil, points: daily.sorted { $0.date < $1.date }.suffix(7).map { $0.values["steps"] ?? nil }, sourceMissing: false),
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

            if let mv = m.value { morning = mv }
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
        }
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

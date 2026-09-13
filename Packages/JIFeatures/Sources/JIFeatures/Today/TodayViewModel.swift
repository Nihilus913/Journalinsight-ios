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

    private let provider: any HealthDataProvider
    private let cache: OfflineCache
    private static let keys = (morning: "today.morning", gate: "today.gate", recovery: "today.recovery")

    public init(provider: any HealthDataProvider, cache: OfflineCache) { self.provider = provider; self.cache = cache }

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
        if let m = try? cache.get(Self.keys.morning, as: MorningResponse.self) { morning = m.value; fetchedAt = m.fetchedAt }
        if let g = try? cache.get(Self.keys.gate, as: GateResponse.self) { gate = g.value }
        if let r = try? cache.get(Self.keys.recovery, as: [RecoveryDay].self) { recovery = r.value }
        if morning != nil { phase = .loaded }
    }

    private func fetchLive() async {
        do {
            async let m = provider.morning()
            async let g = provider.gate(windowDays: 28)
            async let r = provider.recovery(windowDays: 28)
            let (mm, gg, rr) = try await (m, g, r)
            morning = mm; gate = gg; recovery = rr
            fetchedAt = Date(); hubReachable = true; hasLiveResult = true
            try? cache.put(Self.keys.morning, mm); try? cache.put(Self.keys.gate, gg); try? cache.put(Self.keys.recovery, rr)
            phase = (mm.verdict == nil && rr.isEmpty) ? .empty : .loaded
        } catch {
            // A tab switch cancels the view's `.task`; that is not a hub outage. Return to `.idle`
            // so `TodayView.task` reloads on the next appearance instead of showing a false error.
            // `hasLiveResult` stays false either way — CODE-1: a cancelled fetch over a WARM cache
            // leaves `phase == .loaded` (from `restoreFromCache`), not `.idle`, so the view's reload
            // trigger must key off `hasLiveResult`, not `phase`.
            if Task.isCancelled { if phase == .loading { phase = .idle }; return }
            // PARITY-3: branch on the stored HubError — a 401 is a token problem, not a network outage,
            // and must never be reported as "hub unreachable" (which would show cached data under a
            // wrong diagnosis and a staleness banner instead of the token-rejected error card).
            switch error as? HubError {
            case .unauthorized:
                hubReachable = true
                phase = .error(Self.describe(error))
            case .network:
                hubReachable = false
                phase = (morning == nil) ? .error(Self.describe(error)) : .loaded
            default:
                hubReachable = true
                phase = (morning == nil) ? .error(Self.describe(error)) : .loaded
            }
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

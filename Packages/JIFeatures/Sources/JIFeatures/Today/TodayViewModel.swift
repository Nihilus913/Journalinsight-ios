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

    private let provider: any HealthDataProvider
    private let cache: OfflineCache
    private static let keys = (morning: "today.morning", gate: "today.gate", recovery: "today.recovery")

    public init(provider: any HealthDataProvider, cache: OfflineCache) { self.provider = provider; self.cache = cache }

    public var verdict: VerdictParts { verdictParts(morning?.verdict) }

    /// Latest recovery day by date (the hub returns newest-first; sort to be safe).
    private var latestRecovery: RecoveryDay? { recovery.max { $0.date < $1.date } }
    public var readiness: Double? { latestRecovery?.readinessScore }

    public var chips: [TodayChip] {
        let caps = provider.capabilities
        let chron = (morning?.hrvSeries ?? []).sorted { $0.date < $1.date }.suffix(7)
        let rec = recovery.sorted { $0.date < $1.date }.suffix(7)
        let today = resolveTodayRow(gate?.daily ?? [])
        return [
            TodayChip(id: "hrv", label: "HRV", value: latestRecovery?.hrvWeeklyAvg, unit: "ms", points: chron.map(\.hrvWeeklyAvg), sourceMissing: !caps.contains(.hrvRMSSD)),
            TodayChip(id: "rhr", label: "RHR", value: latestRecovery?.rhrBpm, unit: "bpm", points: rec.map(\.rhrBpm), sourceMissing: false),
            TodayChip(id: "sleep", label: "Sleep", value: latestRecovery?.sleepScore, unit: nil, points: rec.map(\.sleepScore), sourceMissing: !caps.contains(.garminSleepScore)),
            TodayChip(id: "steps", label: "Steps", value: today.row?.values["steps"] ?? nil, unit: nil, points: (gate?.daily ?? []).sorted { $0.date < $1.date }.suffix(7).map { $0.values["steps"] ?? nil }, sourceMissing: false),
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
            fetchedAt = Date(); hubReachable = true
            try? cache.put(Self.keys.morning, mm); try? cache.put(Self.keys.gate, gg); try? cache.put(Self.keys.recovery, rr)
            phase = (mm.verdict == nil && rr.isEmpty) ? .empty : .loaded
        } catch {
            hubReachable = false
            if morning == nil { phase = .error(Self.describe(error)) } else { phase = .loaded }
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

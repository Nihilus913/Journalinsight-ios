import Foundation
import Observation
import JICore
import JIPersistence

/// Recovery screen view model (W2b-L2). Mirrors `TodayViewModel`'s phase discipline (CODE-1 /
/// PARITY-7) but over a single section — `provider.recovery(windowDays:)` — instead of Today's
/// three. Reuses `ScreenState` (DESIGN-7) by mapping this VM's own `Phase` onto
/// `TodayViewModel.Phase` at the `screenState` boundary; `verdictDate` is repurposed as "the
/// newest recovery day's date", so a hub that hasn't synced today still flags via
/// `.staleVerdictDate` the same way a stale morning verdict does on Today.
@Observable @MainActor
public final class RecoveryViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var days: [RecoveryDay] = []
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    /// True once a live fetch has actually completed (success or non-cancellation failure with
    /// cache fallback) — mirrors `TodayViewModel.hasLiveResult` (CODE-1: a cancelled fetch over a
    /// warm cache must still re-fetch live on next appearance, keyed off this, not `phase`).
    public private(set) var hasLiveResult = false
    public private(set) var lastError: HubError?

    private let provider: any HealthDataProvider
    private let cache: OfflineCache
    private let now: () -> Date
    private static let key = "recovery.days"
    /// Whether recovery has ever synced successfully — set from a warm cache or the first clean
    /// live fetch, never cleared by a later failure (mirrors `TodayViewModel.everSynced`).
    private var everSynced = false
    private var neverSyncedObserved = false

    /// W2c-L1 snapshot wiring seam — mirrors `TodayViewModel.onSectionUpdate` (see its doc comment
    /// for why this stays a bare closure instead of a `JISnapshot` dependency here).
    public var onSectionUpdate: (() -> Void)?

    public init(provider: any HealthDataProvider, cache: OfflineCache, now: @escaping () -> Date = Date.init) {
        self.provider = provider; self.cache = cache; self.now = now
    }

    /// DESIGN-7 screen state, reused from Today's `ScreenState.resolve` — see the type doc above
    /// for how `Phase`/`verdictDate` are repurposed for a single-section screen.
    public var screenState: ScreenState {
        ScreenState.resolve(
            phase: mappedPhase,
            neverSynced: neverSyncedObserved,
            verdictDate: latestDate,
            todayDateString: todayDateString,
            lastError: lastError
        )
    }

    private var mappedPhase: TodayViewModel.Phase {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .empty: .empty
        case .error(let message): .error(message)
        }
    }

    private var latestDate: String? { days.map(\.date).max() }
    private var todayDateString: String { String(now().ISO8601Format().prefix(10)) }

    /// Newest day's readiness score — `nil` only when there is no day with a non-nil score, never
    /// coerced to `0` (rule 5).
    public var latestReadiness: Double? { newestNonNil(\.readinessScore) }
    public var latestSleepScore: Double? { newestNonNil(\.sleepScore) }
    public var latestSleepDurationSec: Double? { newestNonNil(\.sleepDurationSec) }

    private func newestNonNil(_ value: (RecoveryDay) -> Double?) -> Double? {
        for day in days.sorted(by: { $0.date > $1.date }) {
            if let v = value(day) { return v }
        }
        return nil
    }

    public func load() async {
        phase = .loading
        restoreFromCache()
        await fetchLive()
    }

    public func refresh() async { await fetchLive() }

    private func restoreFromCache() {
        if let hit = try? cache.get(Self.key, as: [RecoveryDay].self) {
            days = hit.value; fetchedAt = hit.fetchedAt; everSynced = true
        }
        if !days.isEmpty { phase = .loaded }
        if !days.isEmpty { onSectionUpdate?() }
    }

    private func fetchLive() async {
        let hadEverSynced = everSynced
        do {
            let provider = self.provider
            let cache = self.cache
            let result = try await SectionLoader.load(key: Self.key, cache: cache) { try await provider.recovery(windowDays: 28) }

            if let value = result.value { days = value }
            fetchedAt = result.fetchedAt ?? fetchedAt
            lastError = result.error

            switch result.error {
            case .some(.unauthorized):
                hubReachable = true
                phase = .error(Self.describe(result.error!))
            case .some(.network):
                hubReachable = false
                phase = days.isEmpty ? .error(Self.describe(result.error!)) : .loaded
            case .some(let e):
                hubReachable = true
                phase = days.isEmpty ? .error(Self.describe(e)) : .loaded
            case .none:
                hubReachable = true
                hasLiveResult = true
                everSynced = true
                let isEmpty = days.isEmpty
                neverSyncedObserved = isEmpty && !hadEverSynced
                phase = isEmpty ? .empty : .loaded
            }
            onSectionUpdate?()
        } catch {
            // A tab switch cancels the view's `.task`; not a hub outage. Return to `.idle` so the
            // view reloads on next appearance instead of showing a false error — mirrors
            // `TodayViewModel.fetchLive`'s cancellation branch verbatim.
            if Task.isCancelled { if phase == .loading { phase = .idle }; return }
            lastError = (error as? HubError) ?? .decoding("\(error)")
            hubReachable = true
            phase = days.isEmpty ? .error(Self.describe(error)) : .loaded
            onSectionUpdate?()
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

// MARK: - B-33 §8.5 fixture

public extension RecoveryViewModel {
    /// A loaded Recovery for `ScreenRegistry`/the screenshot sweep. `nil` only when an in-memory
    /// SQLite file cannot be opened. Never used by the app.
    static func fixture() -> RecoveryViewModel? {
        guard let cache = NativeFixtureStore.cache else { return nil }
        let model = RecoveryViewModel(provider: MockDataProvider(), cache: cache)
        model.days = (0..<7).map { i in
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
        return model
    }
}

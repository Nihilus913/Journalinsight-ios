import Foundation
import Observation
import JICore
import JIPersistence

/// Nutrition screen view model (W3a-L2). Two independently-loadable sections (PARITY-7, same
/// discipline as `RecoveryViewModel`): the selected day's meal-timeline detail and the 7-day week
/// strip. `provider` is `any NutritionProviding` (this screen's own protocol — the Data seam), not
/// the frozen `HealthDataProvider`.
@Observable @MainActor
public final class NutritionViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var selectedDate: String
    /// W-FIX7 N-1: the selected day and the week, Apple Health first — Health's day totals for
    /// every day Health has food, the hub's YAZIO rows only for the days it lacks (the meal list
    /// stays YAZIO's; Health holds day sums only). The hub's own rows are `hubDay` / `hubWeek`.
    public var day: NutritionDayDetail? { NutritionDayDetail.mergingHealth(hubDay, date: selectedDate, health: health.totals) }
    public var week: [NutritionDailyRow] {
        let totals = health.totals
        let merged = NutritionDailyRow.mergingHealth(hubWeek, health: totals)
        guard totals.contains(where: \.hasFood) else { return merged }
        // Health adds days the stale hub lacks: keep the strip's seven newest days.
        let keep = Set(merged.map(\.date).sorted().suffix(7))
        return merged.filter { keep.contains($0.date) }
    }
    private var hubDay: NutritionDayDetail?
    private var hubWeek: [NutritionDailyRow] = []
    private var health: HealthTotalsSource
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    /// Mirrors `RecoveryViewModel.hasLiveResult` — see its doc comment (CODE-1).
    public private(set) var hasLiveResult = false
    public private(set) var lastError: HubError?

    public let provider: any NutritionProviding
    private let cache: OfflineCache
    private let now: () -> Date
    private var everSynced = false
    private var neverSyncedObserved = false

    private static func dayKey(_ date: String) -> String { "nutrition.day.\(date)" }
    private static let weekKey = "nutrition.week"

    public init(provider: any NutritionProviding, cache: OfflineCache, now: @escaping () -> Date = Date.init, initialDate: String? = nil,
                healthFeed: HealthDailyTotalsFeed = .shared) {
        self.health = HealthTotalsSource(feed: healthFeed)
        self.provider = provider
        self.cache = cache
        self.now = now
        self.selectedDate = initialDate ?? String(now().ISO8601Format().prefix(10))
    }

    public var screenState: ScreenState {
        ScreenState.resolve(phase: mappedPhase, neverSynced: neverSyncedObserved, verdictDate: nil, todayDateString: todayDateString, lastError: lastError)
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

    private var todayDateString: String { String(now().ISO8601Format().prefix(10)) }

    public func load() async {
        phase = .loading
        restoreFromCache()
        await fetchLive()
    }

    public func refresh() async { await fetchLive() }

    /// Date-nav / week-strip drilldown (mirrors `nutrition.tsx`'s `setSelectedDate`) — re-queries
    /// that date's meal detail in place rather than resetting the whole screen.
    public func selectDate(_ date: String) async {
        guard date != selectedDate else { return }
        selectedDate = date
        if let hit = try? cache.get(Self.dayKey(date), as: NutritionDayDetail?.self) { hubDay = hit.value }
        else { hubDay = nil }
        await fetchDayLive()
    }

    private func restoreFromCache() {
        health.restore(from: cache)
        var hasAny = false
        if let hit = try? cache.get(Self.dayKey(selectedDate), as: NutritionDayDetail?.self) {
            hubDay = hit.value; fetchedAt = hit.fetchedAt; hasAny = true
        }
        if let hit = try? cache.get(Self.weekKey, as: [NutritionDailyRow].self) {
            hubWeek = hit.value; hasAny = true
        }
        if hasAny { everSynced = true; phase = .loaded }
    }

    private func fetchDayLive() async {
        let provider = self.provider
        let cache = self.cache
        let date = selectedDate
        let result = await (try? SectionLoader.load(key: Self.dayKey(date), cache: cache) { try await provider.nutritionDay(date: date) })
        if let result, date == selectedDate {
            hubDay = result.value ?? hubDay
            lastError = result.error ?? lastError
        }
    }

    private func fetchLive() async {
        let hadEverSynced = everSynced
        let provider = self.provider
        let cache = self.cache
        let date = selectedDate

        async let dayResultTask = SectionLoader.load(key: Self.dayKey(date), cache: cache) { try await provider.nutritionDay(date: date) }
        async let weekResultTask = SectionLoader.load(key: Self.weekKey, cache: cache) { try await provider.nutritionWeek(windowDays: 7) }

        do {
            let (dayResult, weekResult) = try await (dayResultTask, weekResultTask)

            if let value = dayResult.value { hubDay = value }
            hubWeek = weekResult.value ?? hubWeek
            fetchedAt = dayResult.fetchedAt ?? weekResult.fetchedAt ?? fetchedAt

            // yazioAuthExpired always wins (named UI contract); otherwise the day section's error
            // takes priority since it drives most of this screen, falling back to the week's.
            let error = [dayResult.error, weekResult.error].first { if case .yazioAuthExpired = $0 { true } else { false } }
                ?? dayResult.error ?? weekResult.error
            lastError = error

            switch error {
            case .some(.unauthorized):
                hubReachable = true
                phase = .error(Self.describe(error!))
            case .some(.network):
                hubReachable = false
                phase = (day == nil && week.isEmpty) ? .error(Self.describe(error!)) : .loaded
            case .some(let e):
                hubReachable = true
                phase = (day == nil && week.isEmpty) ? .error(Self.describe(e)) : .loaded
            case .none:
                hubReachable = true
                hasLiveResult = true
                everSynced = true
                let isEmpty = day == nil && week.isEmpty
                neverSyncedObserved = isEmpty && !hadEverSynced
                phase = isEmpty ? .empty : .loaded
            }
        } catch {
            // Mirrors RecoveryViewModel.fetchLive's cancellation branch verbatim (CODE-1) — a tab
            // switch cancels the view's `.task`, not a hub outage.
            if Task.isCancelled { if phase == .loading { phase = .idle }; return }
            lastError = (error as? HubError) ?? .decoding("\(error)")
            hubReachable = true
            phase = (day == nil && week.isEmpty) ? .error(Self.describe(error)) : .loaded
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

/// W-FIX7 N-1: the Apple Health day totals a screen merges over the hub's YAZIO rows — the last
/// read the App published to `HealthDailyTotalsFeed` (each foreground), else the plan band's
/// cached totals from an earlier launch (`EnergyBandService.cacheKey`), so a cold start does not
/// flash YAZIO before the first Health read lands. Reading `totals` in a view's body observes the
/// feed, so a fresh read re-renders the screen.
@MainActor struct HealthTotalsSource {
    let feed: HealthDailyTotalsFeed
    private var cached: [HealthDailyTotals] = []
    init(feed: HealthDailyTotalsFeed) { self.feed = feed }
    mutating func restore(from cache: OfflineCache) {
        if let hit = try? cache.get(EnergyBandService.cacheKey, as: [HealthDailyTotals].self) { cached = hit.value }
    }
    var totals: [HealthDailyTotals] {
        let live = feed.latest
        return live.isEmpty ? cached : live
    }
}

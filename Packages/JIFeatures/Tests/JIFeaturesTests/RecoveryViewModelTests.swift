import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// A provider that can be told to fail, to exercise the cache fallback. Mirrors
/// `TodayViewModelTests.FlakyProvider` but lives in this file — JIFeaturesTests has no shared
/// test-support target, and Today/Recovery test files stay independently readable (CLAUDE.md
/// rule: don't touch Today/'s owned files).
nonisolated struct RecoveryFlakyProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    let failing: Bool
    let error: HubError
    init(failing: Bool, error: HubError = .network("simulated")) { self.failing = failing; self.error = error }
    func health() async throws -> HealthResponse { try guardFail(); return try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try guardFail(); return try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try guardFail(); return try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try guardFail(); return try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try guardFail(); return try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try guardFail(); return try await inner.syncStatus() }
    private func guardFail() throws { if failing { throw error } }
}

/// Every call parks until cancelled — models a fetch interrupted by a tab switch (mirrors
/// `TodayViewModelTests.SlowProvider`).
nonisolated struct RecoverySlowProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    private func park<T>() async throws -> T { try await Task.sleep(for: .seconds(30)); throw HubError.network("unreachable test path") }
    func health() async throws -> HealthResponse { try await park() }
    func gate(windowDays: Int) async throws -> GateResponse { try await park() }
    func morning() async throws -> MorningResponse { try await park() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await park() }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await park() }
    func syncStatus() async throws -> SyncStatus { try await park() }
}

/// Always succeeds with an empty `days` array — exercises the never-synced/empty distinction.
nonisolated struct RecoveryEmptyProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    func health() async throws -> HealthResponse { try await MockDataProvider().health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await MockDataProvider().gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await MockDataProvider().morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await MockDataProvider().morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
    func syncStatus() async throws -> SyncStatus { try await MockDataProvider().syncStatus() }
}

@Test @MainActor func recoveryLiveLoadPopulatesAndCaches() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = RecoveryViewModel(provider: RecoveryFlakyProvider(failing: false), cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable)
    #expect(vm.days.isEmpty == false)
    #expect(try cache.get("recovery.days", as: [RecoveryDay].self) != nil)
}

@Test @MainActor func recoveryHubDownFallsBackToCacheAndFlagsStale() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    await RecoveryViewModel(provider: RecoveryFlakyProvider(failing: false), cache: cache).load()   // warm the cache
    let vm = RecoveryViewModel(provider: RecoveryFlakyProvider(failing: true), cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable == false)
    #expect(vm.fetchedAt != nil)
    #expect(vm.days.isEmpty == false)
}

@Test @MainActor func recoveryEmptyWhenNoDays() async throws {
    let vm = RecoveryViewModel(provider: RecoveryEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.phase == .empty)
    #expect(vm.days.isEmpty)
}

@Test @MainActor func recoveryCancelledLoadReturnsToIdle() async throws {
    let vm = RecoveryViewModel(provider: RecoverySlowProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
    let t = Task { await vm.load() }
    try await Task.sleep(for: .milliseconds(50))
    t.cancel()
    await t.value
    #expect(vm.phase == .idle)
    #expect(vm.hubReachable)
    #expect(vm.hasLiveResult == false)
}

@Test @MainActor func screenStateFlagsNeverSyncedAndStaleVerdict() async throws {
    // Never-synced: a genuinely empty first-ever response, no prior cache.
    let neverSynced = RecoveryViewModel(provider: RecoveryEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await neverSynced.load()
    #expect(neverSynced.screenState == .neverSynced)

    // Stale-verdict-date analog: fixture `vitals_recovery.json`'s newest day is "2026-09-11" —
    // when `now` reports a later date, screenState flags it instead of silently reporting `.loaded`.
    let later = try #require(ISO8601DateFormatter().date(from: "2026-09-13T08:00:00Z"))
    let stale = RecoveryViewModel(provider: RecoveryFlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()), now: { later })
    await stale.load()
    #expect(stale.phase == .loaded)
    #expect(stale.screenState == .staleVerdictDate("2026-09-11"))

    // yazioAuthExpired still takes priority over everything else, mirroring TodayViewModel.
    let expired = RecoveryViewModel(provider: RecoveryFlakyProvider(failing: true, error: .yazioAuthExpired(detail: "token stale")), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await expired.load()
    #expect(expired.screenState == .yazioAuthExpired(detail: "token stale"))
}

import Foundation
import Testing
import JICore
import JIHub
import JIPersistence
@testable import JIFeatures

/// A `HealthDataProvider` whose `health()` outcome can be flipped between probes — an `actor` so
/// the mutable flag is safe without `@unchecked Sendable` (same choice as `ToggleProvider`).
actor WatchdogToggleProvider: HealthDataProvider {
    nonisolated let capabilities: DataCapability = .hubAll
    private nonisolated let inner = MockDataProvider()
    private var down: Bool
    private(set) var probes = 0
    init(down: Bool) { self.down = down }
    func setDown(_ value: Bool) { down = value }

    func health() async throws -> HealthResponse {
        probes += 1
        if down { throw HubError.network("simulated outage") }
        return try await inner.health()
    }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
}

// MARK: - Watchdog → outbox recovery drain

@Test @MainActor func hubRecoveryDrainsThePendingWeighInExactlyOnce() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider()
    let drainer = OutboxDrainer(outbox: outbox, provider: weighIn)

    // A weigh-in saved while the Mac was asleep: enqueued, first delivery attempt failed.
    weighIn.error = .network("offline")
    let id = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.4, date: "2026-09-18"))
    await drainer.drainOnce()
    #expect(try outbox.pending().count == 1)

    let hub = WatchdogToggleProvider(down: true)
    let watchdog = HubWatchdog(provider: hub, interval: .seconds(45))
    watchdog.onReachableAgain = { await drainer.drainOnForeground() }

    await watchdog.probe()
    #expect(watchdog.reachable == false)
    #expect(try outbox.pending().count == 1) // still down — nothing drained

    // Hub comes back: one transition, one drain pass, row retired.
    weighIn.error = nil
    await hub.setDown(false)
    await watchdog.probe()
    #expect(watchdog.reachable == true)
    #expect(try outbox.pending().isEmpty)
    #expect(try outbox.pending().contains { $0.id == id } == false)

    // A second healthy probe is not a transition — no second pass to re-deliver anything.
    await watchdog.probe()
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func drainOnForegroundIsAFullDrainPass() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider()
    let drainer = OutboxDrainer(outbox: outbox, provider: weighIn)
    let id = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 80.0, date: "2026-09-18"))

    let results = await drainer.drainOnForeground()

    guard case .success(.weighIn(let r)) = results[id] else { Issue.record("expected weigh-in success"); return }
    #expect(r.weightKg == 80.0)
    #expect(try outbox.pending().isEmpty)
}

// MARK: - SectionLoader: stale by age, not only by failure

private func ageSyncStatus(_ lastSync: String) throws -> SyncStatus {
    try JSON.decoder.decode(SyncStatus.self, from: Data("{\"last_sync\":\"\(lastSync)\"}".utf8))
}

@Test func restoredCacheWithinTheFloorIsFresh() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put("test.age", try ageSyncStatus("2026-09-18T05:00:00Z"))
    let cachedAt = try #require(try cache.fetchedAt("test.age"))

    let result = SectionLoader.restore(key: "test.age", cache: cache, now: cachedAt.addingTimeInterval(44), as: SyncStatus.self)

    #expect(result.value?.lastSync == "2026-09-18T05:00:00Z")
    #expect(result.stale == false)
    #expect(result.error == nil) // nothing was attempted, so nothing failed
}

@Test func restoredCacheOlderThanTheFloorIsStaleWithoutAnyFailure() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put("test.age", try ageSyncStatus("2026-09-18T05:00:00Z"))
    let cachedAt = try #require(try cache.fetchedAt("test.age"))

    let result = SectionLoader.restore(key: "test.age", cache: cache, now: cachedAt.addingTimeInterval(45), as: SyncStatus.self)

    #expect(result.value?.lastSync == "2026-09-18T05:00:00Z") // still rendered — cached, not blank
    #expect(result.stale == true)
    #expect(result.error == nil)
}

@Test func restoringAMissIsStaleAndEmpty() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let result = SectionLoader.restore(key: "test.missing", cache: cache, now: Date(), as: SyncStatus.self)
    #expect(result.value == nil)
    #expect(result.fetchedAt == nil)
    #expect(result.stale == true) // "we have nothing" is never freshness
}

@Test func liveSuccessIsStampedWithTheInjectedClockAndNeverStale() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let stamp = Date(timeIntervalSince1970: 1_758_000_500)
    let result = try await SectionLoader.load(key: "test.age", cache: cache, now: { stamp }) {
        try ageSyncStatus("2026-09-18T06:00:00Z")
    }
    #expect(result.fetchedAt == stamp)
    #expect(result.stale == false)
}

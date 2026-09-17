import Foundation
import Testing
import JICore
import JIFeatures
import JIHub
import JIPersistence
import JISnapshot
@testable import JournalInsight

/// P-snapshot-wiring (W2c-L1) exit criterion: "after a fetch, the App-Group store holds current
/// verdict/readiness/KPIs (integration test, shared suite); no token in the snapshot."
///
/// Uses a real `UserDefaults(suiteName:)` domain (not the production App Group — a unit test has
/// no entitlement to that) so the round trip through `SnapshotStore`'s actual read/write path is
/// exercised exactly as the Watch/Widgets extensions will exercise it, per-test-isolated by a
/// unique suite name and torn down after.
@Suite(.serialized)
struct SnapshotWiringTests {
    private func makeStore() -> (SnapshotStore, String) {
        let suite = "ji.test.snapshot.\(UUID().uuidString)"
        return (SnapshotStore(suiteName: suite), suite)
    }

    private func teardown(_ suite: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    @Test @MainActor func fetchPublishesVerdictReadinessAndKpisToSharedSuite() async throws {
        let (store, suite) = makeStore()
        defer { teardown(suite) }

        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store)
        let today = TodayViewModel(provider: MockDataProvider(), cache: env.cache, prefs: env.prefs)
        let recovery = RecoveryViewModel(provider: MockDataProvider(), cache: env.cache)
        env.bind(today: today, recovery: recovery)

        #expect(store.read() == nil) // nothing published before any fetch

        await today.load()
        await recovery.load()

        let snapshot = try #require(store.read())
        #expect(snapshot.verdictWord != "—") // real verdict from the fixture, not the "no data" placeholder
        #expect(["go", "amber", "red", "muted"].contains(snapshot.verdictTone))
        #expect(snapshot.readiness != nil)
        #expect(!snapshot.kpis.isEmpty)
        #expect(snapshot.kpis.contains { $0.label == "HRV" })
        #expect(snapshot.lastSync != nil)

        // No token, or anything token-shaped, anywhere in the persisted payload.
        let encoded = try JSONEncoder().encode(snapshot)
        let json = String(decoding: encoded, as: UTF8.self).lowercased()
        #expect(!json.contains("token"))
        #expect(!json.contains("bearer"))
    }

    /// CODE-1 shape (a cold app relaunch over a warm cache, hub unreachable this time): the
    /// snapshot must still reflect the cached verdict/readiness rather than staying empty just
    /// because the live fetch that follows fails — `restoreFromCache`'s own publish (not only
    /// `fetchLive`'s) is what's under test here.
    @Test @MainActor func warmCacheStillPublishesWhenTheFollowingLiveFetchFails() async throws {
        let (store, suite) = makeStore()
        defer { teardown(suite) }

        let sharedCache = OfflineCache(db: try AppDatabase.inMemory())
        let warmEnv = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: SnapshotStore(suiteName: "ji.test.snapshot.\(UUID().uuidString)"))
        let warmToday = TodayViewModel(provider: MockDataProvider(), cache: sharedCache, prefs: warmEnv.prefs)
        let warmRecovery = RecoveryViewModel(provider: MockDataProvider(), cache: sharedCache)
        await warmToday.load()
        await warmRecovery.load()
        #expect(warmToday.morning != nil) // cache now warm

        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store)
        let today = TodayViewModel(provider: AlwaysFailingProvider(), cache: sharedCache, prefs: env.prefs)
        let recovery = RecoveryViewModel(provider: AlwaysFailingProvider(), cache: sharedCache)
        env.bind(today: today, recovery: recovery)

        await today.load()
        await recovery.load()

        let snapshot = try #require(store.read())
        #expect(snapshot.verdictWord != "—")
        #expect(snapshot.readiness != nil)
    }
}

nonisolated struct AlwaysFailingProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    func health() async throws -> HealthResponse { throw HubError.network("simulated") }
    func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("simulated") }
    func morning() async throws -> MorningResponse { throw HubError.network("simulated") }
    func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("simulated") }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { throw HubError.network("simulated") }
    func syncStatus() async throws -> SyncStatus { throw HubError.network("simulated") }
}

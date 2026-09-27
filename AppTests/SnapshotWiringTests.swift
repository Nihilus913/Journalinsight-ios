import Foundation
import Testing
import JICore
import JIFeatures
import JIHub
import JIPersistence
import JISnapshot
import JICompute
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
    /// W-FIX1 BUG-05: readiness is "last night" only while that night is ≤ 36 h old, so the clock
    /// is pinned to the dated `MockDataProvider` fixture's newest night (2026-09-11).
    private static let fixtureNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_789_128_000) } // 2026-09-11T12:00Z

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
        let today = TodayViewModel(provider: MockDataProvider(), cache: env.cache, prefs: env.prefs, now: Self.fixtureNow)
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
        let warmToday = TodayViewModel(provider: MockDataProvider(), cache: sharedCache, prefs: warmEnv.prefs, now: Self.fixtureNow)
        let warmRecovery = RecoveryViewModel(provider: MockDataProvider(), cache: sharedCache)
        await warmToday.load()
        await warmRecovery.load()
        #expect(warmToday.morning != nil) // cache now warm

        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store)
        let today = TodayViewModel(provider: AlwaysFailingProvider(), cache: sharedCache, prefs: env.prefs, now: Self.fixtureNow)
        let recovery = RecoveryViewModel(provider: AlwaysFailingProvider(), cache: sharedCache)
        env.bind(today: today, recovery: recovery)

        await today.load()
        await recovery.load()

        let snapshot = try #require(store.read())
        #expect(snapshot.verdictWord != "—")
        #expect(snapshot.readiness != nil)
    }

    /// B-57 W5 A6: the glances get the reason, the user's cap AS STORED (nil = none, no fallback),
    /// the HRV/Sleep/RHR triple, and — through `glancePlan` — the week's plan progress.
    @Test @MainActor func snapshotCarriesReasonCapAndSignals() async throws {
        let (store, suite) = makeStore()
        defer { teardown(suite) }
        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store)
        let today = TodayViewModel(provider: MockDataProvider(), cache: env.cache, prefs: env.prefs, now: Self.fixtureNow)
        let recovery = RecoveryViewModel(provider: MockDataProvider(), cache: env.cache)
        env.bind(today: today, recovery: recovery)
        await today.load()

        let s = try #require(store.read())
        #expect(s.hrCap == nil)                          // a fresh install has no cap — none is invented
        #expect(s.signals?.map(\.key) == ["hrv", "sleep_h", "rhr"])
        #expect((s.reason ?? "").count <= 48)
        #expect(s.reason == HubSnapshot.reasonLine(from: today.morning?.gateSignals))
        #expect(s.planDone == nil && s.planTotal == nil && s.nextSession == nil)   // no week known: nothing invented

        try GateSettingsStore(prefs: env.prefs).save(GateSettings(preset: .balanced, hrCapBpm: 168, hrCapConfirmedOn: "2026-09-24"))
        env.republishSnapshot()
        #expect(store.read()?.hrCap == 168)

        try GateSettingsStore(prefs: env.prefs).save(.legacyPreW4)                  // Toby's migrated, unconfirmed 175
        env.republishSnapshot()
        #expect(store.read()?.hrCap == 175)

        try GateSettingsStore(prefs: env.prefs).save(GateSettings(hrCapBpm: nil, hrCapConfirmedOn: "2026-09-25"))
        env.republishSnapshot()
        #expect(store.read()?.hrCap == nil)

        env.glancePlan = { GlancePlan(done: 1, total: 4, next: "Fri · Day 3 Full Upper") }
        env.republishSnapshot()
        let planned = try #require(store.read())
        #expect(planned.planDone == 1 && planned.planTotal == 4 && planned.nextSession == "Fri · Day 3 Full Upper")
        env.glancePlan = { GlancePlan(done: 0, total: 0, next: nil) }            // an empty plan is "no plan", not "0 of 0"
        env.republishSnapshot()
        #expect(store.read()?.planTotal == nil)
    }

    /// B-57 W5 A6: HRV / RHR normals from W3's recovery insight reach the KPI entries and signals.
    @Test @MainActor func recoveryNormalsReachTheGlances() async throws {
        let (store, suite) = makeStore()
        defer { teardown(suite) }
        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store)
        let insight = try #require(RecoveryInsightService.galleryFixture)
        env.recoveryInsight = insight
        let today = TodayViewModel(provider: MockDataProvider(), cache: env.cache, prefs: env.prefs, now: Self.fixtureNow)
        env.bind(today: today, recovery: nil)
        await today.load()
        let s = try #require(store.read())
        let hrvNormal = try #require(insight.normal(for: .hrv)?.range)
        #expect(s.signal("hrv")?.normalLow == hrvNormal.lowerBound)
        #expect(s.signal("hrv")?.normalHigh == hrvNormal.upperBound)
        #expect(s.kpi(.hrv)?.normalLow == hrvNormal.lowerBound)
        #expect(s.kpi(.rhr)?.normalLow == insight.normal(for: .rhr)?.range.lowerBound)
    }

    /// W-B57-W5 PF-04: the glances' sync moment is the one sync-pill rule — Today's `syncedAt`
    /// (newer of the hub's last sync and the last HealthKit upload), never the moment of a fetch.
    @Test @MainActor func glanceSyncTimeIsTheOneSyncRule() async throws {
        let (store, suite) = makeStore()
        defer { teardown(suite) }
        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store)
        let today = TodayViewModel(provider: MockDataProvider(), cache: env.cache, prefs: env.prefs, now: Self.fixtureNow)
        let recovery = RecoveryViewModel(provider: MockDataProvider(), cache: env.cache)
        env.bind(today: today, recovery: recovery)
        await today.load()
        await recovery.load()
        let s = try #require(store.read())
        #expect(today.syncedAt != nil)
        #expect(s.lastSync == today.syncedAt)
        #expect(s.lastSync != today.fetchedAt && s.lastSync != recovery.fetchedAt)
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

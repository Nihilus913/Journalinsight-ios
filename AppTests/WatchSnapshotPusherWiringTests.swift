import Foundation
import Testing
import JICore
import JIFeatures
import JIHub
import JIPersistence
import JISnapshot
import JIWorkouts
@testable import JournalInsight

/// W-B78 B78-2 (App wiring; unit cases: JISnapshotTests/WatchSnapshotPusherTests): the phone pushes the HubSnapshot to the Watch over the ONE shared
/// WatchConnectivity transport (Fake here), merged into the application context.
@Suite(.serialized) @MainActor
struct WatchSnapshotPusherWiringTests {
    private static let fixtureNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_789_128_000) } // 2026-09-11T12:00Z

    private func snapshot(word: String = "GO", fetchedAt: Date = Date(timeIntervalSince1970: 1_789_128_000)) -> HubSnapshot {
        HubSnapshot(verdictWord: word, verdictSession: "Easy run", verdictTone: "go", verdictDate: "2026-09-11", readiness: 78,
                    kpis: [SnapshotKPI(label: "HRV", value: 52, unit: "ms")],
                    fetchedAt: fetchedAt, lastSync: Date(timeIntervalSince1970: 1_789_128_000))
    }

    private func pushed(_ fake: FakeStrengthBridgeTransport) -> HubSnapshot? {
        SnapshotWire.snapshot(in: fake.applicationContext)
    }

    @Test func pushAfterWriteFromAppEnvironment() async throws {
        let suite = "ji.test.snapshot.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = SnapshotStore(suiteName: suite)
        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store, now: Self.fixtureNow)
        let fake = FakeStrengthBridgeTransport()
        let pusher = WatchSnapshotPusher(isWatchAppInstalled: { true })
        pusher.transport = fake
        env.watchSnapshotPusher = pusher
        let today = TodayViewModel(provider: MockDataProvider(), cache: env.cache, prefs: env.prefs, now: Self.fixtureNow)
        let recovery = RecoveryViewModel(provider: MockDataProvider(), cache: env.cache)
        env.bind(today: today, recovery: recovery)

        await today.load()
        await recovery.load()

        let written = try #require(store.read())
        let onWire = try #require(pushed(fake))
        #expect(onWire.verdictWord == written.verdictWord)
        #expect(onWire.verdictWord != "—")
        #expect(onWire == written)
    }

    @Test func planKeyRetainedWithStrengthFake() throws {
        let fake = FakeStrengthBridgeTransport()
        let planBytes = Data("plan".utf8)
        try fake.mergeApplicationContext(key: StrengthBridgeKeys.plan, value: planBytes)
        let pusher = WatchSnapshotPusher(isWatchAppInstalled: { true })
        pusher.transport = fake
        pusher.push(snapshot())
        #expect(fake.applicationContext[StrengthBridgeKeys.plan] as? Data == planBytes)
        #expect(pushed(fake)?.verdictWord == "GO")
    }
}

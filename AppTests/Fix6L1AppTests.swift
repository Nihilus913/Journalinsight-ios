import Foundation
import Testing
import JICore
import JIFeatures
import JIHub
import JIPersistence
import JISnapshot
@testable import JournalInsight

/// W-FIX6 L1 — the glances (widgets, Live Activity) carry Decide's call (F6-11) and the
/// recovery normals once the insight has loaded (F6-2).
@Suite(.serialized)
struct Fix6L1AppTests {
    /// 2026-09-28T05:32:00+02:00.
    private static let now0928: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_790_566_320) }

    private struct Hub0928: HealthDataProvider {
        var capabilities: DataCapability { .hubAll }
        func health() async throws -> HealthResponse { HealthResponse(status: "ok") }
        func gate(windowDays: Int) async throws -> GateResponse { try await MockDataProvider().gate(windowDays: windowDays) }
        func morning() async throws -> MorningResponse {
            try JSON.decoder.decode(MorningResponse.self, from: Data(fix6Morning20260928JSON.utf8))
        }
        func morningVerdict(date: String) async throws -> MorningVerdict { try await MockDataProvider().morningVerdict(date: date) }
        func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
        func syncStatus() async throws -> SyncStatus { SyncStatus(lastSync: nil) }
    }

    private func makeEnv() throws -> (AppEnvironment, SnapshotStore, String) {
        let suite = "ji.test.fix6l1.\(UUID().uuidString)"
        let store = SnapshotStore(suiteName: suite)
        return (try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: store), store, suite)
    }

    @Test @MainActor func widgetAndLiveActivityCarryDecidesCall() async throws {
        let (env, store, suite) = try makeEnv()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        var activity: [HubSnapshot] = []
        env.liveActivity = { activity.append($0) }
        let today = TodayViewModel(provider: Hub0928(), cache: env.cache, prefs: env.prefs, now: Self.now0928, uploadRecord: nil)
        env.bind(today: today, recovery: nil)
        await today.load()
        let decide = today.headline(override: nil)
        let snap = try #require(store.read())
        #expect(snap.verdictWord == decide.word)
        #expect(snap.verdictWord == "Modified")
        #expect(snap.verdictSession == "Day 1 Full Upper + Z2 40min")
        #expect(snap.verdictTone == "amber")
        #expect(snap.verdictDate == "2026-09-28")
        let live = try #require(activity.last)
        #expect(live.verdictWord == decide.word && live.verdictSession == decide.session)
    }

    @Test @MainActor func theUsersOverrideReachesTheGlances() async throws {
        let (env, store, suite) = try makeEnv()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        env.liveActivity = nil
        let today = TodayViewModel(provider: Hub0928(), cache: env.cache, prefs: env.prefs, now: Self.now0928, uploadRecord: nil)
        env.bind(today: today, recovery: nil)
        env.currentOverride = { VerdictOverride(date: "2026-09-28", choice: .rest, reason: nil, session: "Rest — walks only") }
        await today.load()
        let snap = try #require(store.read())
        #expect(snap.verdictWord == "Rest")
        #expect(snap.verdictSession == "Rest — walks only")
    }

    /// F6-2: a launch onto More published the glance before the recovery insight loaded, so the
    /// medium widget said "no normal"; once the insight lands the glance is republished with it.
    @Test @MainActor func glanceIsRepublishedWhenTheInsightLoads() async throws {
        let (env, store, suite) = try makeEnv()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        env.liveActivity = nil
        let insight = RecoveryInsightService(provider: MockDataProvider(), cache: env.cache)
        env.recoveryInsight = insight
        let today = TodayViewModel(provider: Hub0928(), cache: env.cache, prefs: env.prefs, now: Self.now0928, uploadRecord: nil)
        env.bind(today: today, recovery: nil)
        await today.load()
        let before = try #require(store.read())
        #expect(before.signals?.first { $0.key == "hrv" }?.normalLow == nil)
        await env.refreshGlanceInsight()
        #expect(insight.normal(for: .hrv) != nil)
        let after = try #require(store.read())
        #expect(after.signals?.first { $0.key == "hrv" }?.normalLow != nil)
    }

    /// F6-11: the verdict source is the hub whatever the tiles' data source is.
    @Test @MainActor func theHubIsTheVerdictSource() {
        struct OnDevice: HealthDataProvider {
            var capabilities: DataCapability { [.recovery] }
            func health() async throws -> HealthResponse { HealthResponse(status: "ok") }
            func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("x") }
            func morning() async throws -> MorningResponse { throw HubError.network("x") }
            func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("x") }
            func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
            func syncStatus() async throws -> SyncStatus { SyncStatus() }
        }
        #expect(RootTabView.verdictSource(hub: Hub0928(), dataSource: OnDevice()) is Hub0928)
        #expect(RootTabView.verdictSource(hub: nil, dataSource: OnDevice()) is OnDevice)
    }
}

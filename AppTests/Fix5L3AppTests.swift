import Foundation
import Testing
import JICore
import JIFeatures
import JISnapshot
import JIHub
import JIPersistence
@testable import JournalInsight

/// W-FIX5 L3: W5-1 (gate medium widget columns) and W5-5 (the app starts the Live Activity).
@Suite(.serialized)
struct Fix5L3AppTests {
    private static let fixtureNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_789_128_000) } // 2026-09-11T12:00Z

    @Test func mediumWidgetKeepsTheCallColumn() {
        for width in [291.0, 306.0, 329.0] {
            let cols = GateMediumLayout.columns(width: width, signalCount: 3)
            #expect(cols.left >= GateMediumLayout.leftMin)
            #expect(cols.signal > 40)
            let used = cols.left + GateMediumLayout.spacing + 3 * cols.signal + 2 * GateMediumLayout.signalSpacing
            #expect(abs(used - width) < 0.001)
        }
        #expect(GateMediumLayout.columns(width: 306, signalCount: 0).left == 306)
    }

    @Test func onlyARealCallDrivesTheLiveActivity() {
        var s = HubSnapshot(verdictWord: "GO", verdictSession: "Full", verdictTone: "go", verdictDate: "2026-09-27", readiness: nil, kpis: [], fetchedAt: .now, lastSync: nil)
        #expect(AppEnvironment.drivesLiveActivity(s))
        s.verdictDate = nil
        #expect(!AppEnvironment.drivesLiveActivity(s))
    }

    @Test func testHostsNeverStartARealActivity() { #expect(AppEnvironment.defaultLiveActivity == nil) }

    @Test @MainActor func publishingAVerdictStartsTheLiveActivity() async throws {
        let suite = "ji.test.fix5l3.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let env = try AppEnvironment(secrets: InMemorySecretStore(), inMemory: true, snapshotStore: SnapshotStore(suiteName: suite))
        var started: [HubSnapshot] = []
        env.liveActivity = { started.append($0) }
        let today = TodayViewModel(provider: MockDataProvider(), cache: env.cache, prefs: env.prefs, now: Self.fixtureNow)
        env.bind(today: today, recovery: nil)
        await today.load()
        let last = try #require(started.last)
        #expect(last.verdictWord != "—")
        #expect(last.verdictDate != nil)
    }
}

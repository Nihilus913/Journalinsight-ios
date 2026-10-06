import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-FIX-P3 RG-69 (B-52): offline copy. Time in zone and Progress rendered the hub's cached
// answer like live data (no "Offline — showing data from …" line, which Month / library /
// Send to Watch already show); Recovery's cold-cache subtitle said "0 nights".

private let rg69CachedAt = ISO8601DateFormatter().date(from: "2026-10-04T07:41:00Z")!
private nonisolated func rg69ServeStale(_ key: String) { HubReadTrace.current?.record(key, fetchedAt: rg69CachedAt) }

private nonisolated final class RG69ZoneHub: ZoneTimeProviding, @unchecked Sendable { // @unchecked: one test actor
    var stale: Bool
    init(stale: Bool) { self.stale = stale }
    func trainingZones(from: String, to: String, bucket: String, scope: String) async throws -> ZoneTimeRange {
        if stale { rg69ServeStale("hub:GET /api/v1/training/zones") }
        return ZoneTimeRange(from: from, to: to, bucket: bucket, scope: scope, floors: nil, hrCapBpm: nil,
                             buckets: [], totals: ZoneTimeTotals(minutes: nil, sessions: 0, sessionsNoHr: 0))
    }
}

private nonisolated final class RG69CardioHub: CardioSeriesProviding, @unchecked Sendable { // @unchecked: one test actor
    var stale: Bool
    init(stale: Bool) { self.stale = stale }
    func cardioSeries(range: String) async throws -> CardioSeries {
        if stale { rg69ServeStale("hub:GET /api/v1/training/cardio-series?range=\(range)") }
        return CardioSeries(range: range, from: "2025-10-05", to: "2026-10-05", runs: [], vo2max: [])
    }
}

@MainActor @Suite(.serialized) struct RG69OfflineCopyTests {

    @Test func timeInZoneSaysOfflineWhileShowingTheCachedCopy() async {
        let hub = RG69ZoneHub(stale: true)
        let m = ZoneTimeModel(provider: hub, today: { DayKey(iso: "2026-10-05")! })
        await m.load()
        #expect(m.staleSince == rg69CachedAt)
        #expect(m.offlineText?.hasPrefix("Offline — showing data from") == true)
        hub.stale = false
        await m.load()
        #expect(m.offlineText == nil)
    }

    @Test func progressSaysOfflineWhileShowingTheCachedCopy() async {
        let hub = RG69CardioHub(stale: true)
        let m = ProgressViewModel(store: nil, provider: nil, cardioProvider: hub, prefStore: nil, today: { "2026-10-05" })
        await m.load()
        #expect(m.offlineText?.hasPrefix("Offline — showing data from") == true)
        hub.stale = false
        await m.load()
        #expect(m.offlineText == nil)
    }

    @Test func recoveryColdCacheSubtitleHasNoFabricatedZero() {
        #expect(recoverySubtitle(nights: 0) == "How you are trending")
        #expect(recoverySubtitle(nights: 1) == "How you are trending · 1 night")
        #expect(recoverySubtitle(nights: 14) == "How you are trending · 14 nights")
    }

    @Test func queuedSyncNoteIsFriendlyWithoutTheRawSystemError() {
        let note = strengthQueuedSyncNote(pending: 2)
        #expect(note == "2 changes saved on this phone — will send when the hub is reachable.")
        #expect(!note.contains("("))
        #expect(strengthQueuedSyncNote(pending: 1) == "1 change saved on this phone — will send when the hub is reachable.")
    }
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// @unchecked: test-only fake; its vars are touched only from the @MainActor test bodies.
final class GateSettingsHubFake: GateSettingsProviding, @unchecked Sendable {
    var puts: [GateSettingsBody] = []
    var fail = false
    func gateSettings() async throws -> GateSettingsDTO {
        GateSettingsDTO(preset: "balanced", hrCapBpm: nil, avoidZone5: false, zoneFloorsBpm: nil, hrvLowNights: 2, updatedAt: nil)
    }
    func putGateSettings(_ body: GateSettingsBody) async throws -> GateSettingsDTO {
        if fail { throw HubError.network("down") }
        puts.append(body)
        return GateSettingsDTO(preset: body.preset, hrCapBpm: body.hrCapBpm, avoidZone5: body.avoidZone5,
                               zoneFloorsBpm: body.zoneFloorsBpm, hrvLowNights: 2, updatedAt: nil)
    }
}

@MainActor struct GateSettingsMirrorTests {
    @Test func saveStoresLocallyThenPushesTheExactBody() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let hub = GateSettingsHubFake()
        let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
        let ok = await mirror.save(GateSettings(preset: .push, hrCapBpm: 168, avoidZone5: true, zones: .legacyPreW4,
                                                hrCapConfirmedOn: "2026-09-24"))
        #expect(ok)
        #expect(hub.puts == [GateSettingsBody(preset: "push", hrCapBpm: 168, avoidZone5: true, zoneFloorsBpm: [97, 117, 139, 160, 176])])
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 168)
        #expect(!mirror.hubPending)
    }

    @Test func noCapIsMirroredAsNoCap() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let hub = GateSettingsHubFake()
        #expect(await GateSettingsMirror(prefs: prefs, provider: hub).save(GateSettings(hrCapBpm: nil, hrCapConfirmedOn: "2026-09-24")))
        #expect(hub.puts == [GateSettingsBody(preset: "balanced", hrCapBpm: nil, avoidZone5: false, zoneFloorsBpm: nil)])
    }

    /// Review Focus 3 — hub offline: the phone keeps the value, GateConfig says "Not on the hub
    /// yet", the next foreground pushes it.
    @Test func offlineSaveKeepsPendingAndRetries() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let hub = GateSettingsHubFake(); hub.fail = true
        let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
        #expect(await mirror.save(GateSettings(preset: .cautious, hrCapBpm: 160)) == false)
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 160)   // the phone keeps it
        #expect(mirror.hubPending)
        #expect(mirror.hubStatusText == "Not on the hub yet")
        hub.fail = false
        #expect(await mirror.pushIfPending())
        #expect(hub.puts.last == GateSettingsBody(preset: "cautious", hrCapBpm: 160, avoidZone5: false, zoneFloorsBpm: nil))
        #expect(!GateSettingsMirror(prefs: prefs, provider: hub).hubPending)   // flag is persisted
        #expect(mirror.hubStatusText == nil)
    }

    /// A retry pushes the LATEST local value, not the one that failed.
    @Test func retryPushesTheLatestLocalValue() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let hub = GateSettingsHubFake(); hub.fail = true
        let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
        await mirror.save(GateSettings(hrCapBpm: 160))
        await mirror.save(GateSettings(preset: .push, hrCapBpm: nil, hrCapConfirmedOn: "2026-09-25"))
        hub.fail = false
        #expect(await mirror.pushIfPending())
        #expect(hub.puts == [GateSettingsBody(preset: "push", hrCapBpm: nil, avoidZone5: false, zoneFloorsBpm: nil)])
    }

    @Test func pushIfPendingIsANoOpWhenNothingIsPending() async throws {
        let hub = GateSettingsHubFake()
        let mirror = GateSettingsMirror(prefs: PrefStore(db: try AppDatabase.inMemory()), provider: hub)
        #expect(await mirror.pushIfPending() == false)
        #expect(hub.puts.isEmpty)
    }

    @Test func noHubStillSavesLocallyAndStaysPending() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let mirror = GateSettingsMirror(prefs: prefs, provider: nil)
        #expect(await mirror.save(GateSettings(hrCapBpm: 170)) == false)
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 170)
        #expect(mirror.hubPending)
    }
}

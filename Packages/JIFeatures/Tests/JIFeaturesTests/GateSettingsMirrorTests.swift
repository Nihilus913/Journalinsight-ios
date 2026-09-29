import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// The Limits + caution rule a pushed targets document carried, in the old W4 wire shape (so the
/// expectations below read as before). Test-only.
struct GatePut: Equatable {
    var preset: String; var hrCapBpm: Int?; var avoidZone5: Bool; var zoneFloorsBpm: [Int]?
    init(preset: String, hrCapBpm: Int?, avoidZone5: Bool, zoneFloorsBpm: [Int]?) {
        self.preset = preset; self.hrCapBpm = hrCapBpm; self.avoidZone5 = avoidZone5; self.zoneFloorsBpm = zoneFloorsBpm
    }
}

/// W-FIX10 F10-1: the gate settings reach the hub only inside the targets document
/// (`PUT /planning/targets`); `PUT /planning/gate-settings` is gone.
// @unchecked: test-only fake; its vars are touched only from the @MainActor test bodies.
final class GateSettingsHubFake: TargetsProviding, @unchecked Sendable {
    var docs: [TargetsDocument] = []
    var fail = false
    var puts: [GatePut] {
        docs.map { d in
            let s = GateSettings(targets: d)
            return GatePut(preset: s.preset.rawValue, hrCapBpm: s.hrCapBpm, avoidZone5: s.avoidZone5, zoneFloorsBpm: s.zones?.floorsBpm)
        }
    }
    func targets() async throws -> TargetsDocument { docs.last ?? .empty }
    func putTargets(_ document: TargetsDocument) async throws -> TargetsDocument {
        if fail { throw HubError.network("down") }
        docs.append(document); return document
    }
}

/// A phone after the §5 targets import (what `TargetsMirror.migrateAtLaunch` leaves at launch).
func postImportPrefs() throws -> PrefStore {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    try TargetsStore(prefs: prefs).save(.empty)
    return prefs
}

@MainActor struct GateSettingsMirrorTests {
    @Test func saveStoresLocallyThenPushesTheExactBody() async throws {
        let prefs = try postImportPrefs()
        let hub = GateSettingsHubFake()
        let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
        let ok = await mirror.save(GateSettings(preset: .push, hrCapBpm: 168, avoidZone5: true, zones: .legacyPreW4,
                                                hrCapConfirmedOn: "2026-09-24"))
        #expect(ok)
        #expect(hub.puts == [GatePut(preset: "push", hrCapBpm: 168, avoidZone5: true, zoneFloorsBpm: [97, 117, 139, 160, 176])])
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 168)
        #expect(!mirror.hubPending)
    }

    @Test func noCapIsMirroredAsNoCap() async throws {
        let prefs = try postImportPrefs()
        let hub = GateSettingsHubFake()
        #expect(await GateSettingsMirror(prefs: prefs, provider: hub).save(GateSettings(hrCapBpm: nil, hrCapConfirmedOn: "2026-09-24")))
        #expect(hub.puts == [GatePut(preset: "balanced", hrCapBpm: nil, avoidZone5: false, zoneFloorsBpm: nil)])
    }

    /// Review Focus 3 — hub offline: the phone keeps the value, GateConfig says "Not on the hub
    /// yet", the next foreground pushes it.
    @Test func offlineSaveKeepsPendingAndRetries() async throws {
        let prefs = try postImportPrefs()
        let hub = GateSettingsHubFake(); hub.fail = true
        let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
        #expect(await mirror.save(GateSettings(preset: .cautious, hrCapBpm: 160)) == false)
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 160)   // the phone keeps it
        #expect(mirror.hubPending)
        #expect(mirror.hubStatusText == "Not on the hub yet")
        hub.fail = false
        #expect(await mirror.pushIfPending())
        #expect(hub.puts.last == GatePut(preset: "cautious", hrCapBpm: 160, avoidZone5: false, zoneFloorsBpm: nil))
        #expect(!GateSettingsMirror(prefs: prefs, provider: hub).hubPending)   // flag is persisted
        #expect(mirror.hubStatusText == nil)
    }

    /// A retry pushes the LATEST local value, not the one that failed.
    @Test func retryPushesTheLatestLocalValue() async throws {
        let prefs = try postImportPrefs()
        let hub = GateSettingsHubFake(); hub.fail = true
        let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
        await mirror.save(GateSettings(hrCapBpm: 160))
        await mirror.save(GateSettings(preset: .push, hrCapBpm: nil, hrCapConfirmedOn: "2026-09-25"))
        hub.fail = false
        #expect(await mirror.pushIfPending())
        #expect(hub.puts == [GatePut(preset: "push", hrCapBpm: nil, avoidZone5: false, zoneFloorsBpm: nil)])
    }

    @Test func pushIfPendingIsANoOpWhenNothingIsPending() async throws {
        let hub = GateSettingsHubFake()
        let mirror = GateSettingsMirror(prefs: try postImportPrefs(), provider: hub)
        #expect(await mirror.pushIfPending() == false)
        #expect(hub.puts.isEmpty)
    }

    @Test func noHubStillSavesLocallyAndStaysPending() async throws {
        let prefs = try postImportPrefs()
        let mirror = GateSettingsMirror(prefs: prefs, provider: nil)
        #expect(await mirror.save(GateSettings(hrCapBpm: 170)) == false)
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 170)
        #expect(mirror.hubPending)
    }

    /// W-FIX10 F10-1: before the §5 import there is no document to send — nothing goes to the hub
    /// (never the removed gate-settings route), the phone keeps the value, the change stays pending.
    @Test func beforeTheImportNothingIsSentAndItStaysPending() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let hub = GateSettingsHubFake()
        let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
        #expect(await mirror.save(GateSettings(hrCapBpm: 170)) == false)
        #expect(hub.docs.isEmpty)
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 170)
        #expect(mirror.hubPending)
    }
}

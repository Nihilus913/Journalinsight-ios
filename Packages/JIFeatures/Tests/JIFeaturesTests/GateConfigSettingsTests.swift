import Foundation
import Observation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// B-57 W4 C2: GateConfig owns the user's preset, optional HR cap (+ 8-week re-check), zones and
// Avoid Zone 5 (Toby 2026-09-24: user input, optional, never an app default or limit).
@MainActor struct GateConfigSettingsTests {
    private func make(hubFails: Bool = false, stored: GateSettings? = nil) throws -> (GateConfigViewModel, PrefStore, FakeNotificationCenter, GateSettingsHubFake) {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        if let stored { try GateSettingsStore(prefs: prefs).save(stored) }
        let hub = GateSettingsHubFake(); hub.fail = hubFails
        let center = FakeNotificationCenter()
        let vm = GateConfigViewModel(prefStore: prefs,
                                     mirror: GateSettingsMirror(prefs: prefs, provider: hub),
                                     reminderCenter: center, today: { "2026-09-24" })
        vm.loadLocal()
        return (vm, prefs, center, hub)
    }

    @Test func settingsFlowIntoTheEffectiveConfig() async throws {
        let (vm, _, _, _) = try make()
        #expect(vm.gateSettings.hrCapBpm == nil && vm.gateSettings.preset.hrvLowNights == 2)   // no app default cap
        await vm.setPreset(.push)
        _ = await vm.changeHrCap("168")
        #expect(vm.gateSettings.preset.hrvLowNights == 3)
        #expect(vm.gateSettings.hrCapBpm == 168)
    }

    @Test func changeHrCapRejectsNonNumbersAndSavesNothing() async throws {
        let (vm, prefs, center, hub) = try make()
        #expect(await vm.changeHrCap("17a") == false)
        #expect(await vm.changeHrCap("175.0") == false)
        #expect(await vm.changeHrCap("") == false)
        #expect(GateSettingsStore(prefs: prefs).load() == GateSettings())
        #expect(center.pending.isEmpty && hub.puts.isEmpty)
    }

    @Test func changeHrCapConfirmsMirrorsAndReschedulesTheRecheck() async throws {
        let (vm, prefs, center, hub) = try make()
        #expect(await vm.changeHrCap(" 182 "))
        let s = GateSettingsStore(prefs: prefs).load()
        #expect(s.hrCapBpm == 182 && s.hrCapConfirmedOn == "2026-09-24")
        #expect(hub.puts.last == .init(preset: "balanced", hrCapBpm: 182, avoidZone5: false, zoneFloorsBpm: nil))
        #expect(await ReminderScheduler(center: center).hrCapCheckDue() == "2026-11-19")
        #expect(vm.capValueText == "182 bpm")
        #expect(vm.capSubtitle == "You chose it in setup. The app never raises it.")
        #expect(vm.recheckSubtitle == "Confirm your HR cap every 8 weeks. Last confirmed 2026-09-24. JI asks; you decide.")
    }

    /// Toby 2026-09-24: removing the cap is the user's call; the re-check goes with it.
    @Test func removingTheCapCancelsTheRecheck() async throws {
        let (vm, prefs, center, hub) = try make()
        _ = await vm.changeHrCap("175")
        #expect(await vm.changeHrCap(nil))
        let s = GateSettingsStore(prefs: prefs).load()
        #expect(s.hrCapBpm == nil && s.hrCapConfirmedOn == "2026-09-24")
        #expect(await ReminderScheduler(center: center).hrCapCheckDue() == nil)
        #expect(hub.puts.last?.hrCapBpm == nil)
        #expect(vm.capValueText == "None")
        #expect(vm.capSubtitle == "You chose no limit. Tap to add one — only you change it.")
        #expect(vm.recheckSubtitle == nil)
    }

    @Test func aFreshInstallSaysNoLimitNotADefault() throws {
        let (vm, _, _, _) = try make()
        #expect(vm.capValueText == "None")
        #expect(vm.capSubtitle == "No limit set. Tap to add one — only you change it.")
        #expect(vm.recheckSubtitle == nil)
        #expect(vm.gateSettings.zones == nil && !vm.gateSettings.avoidZone5)
    }

    @Test func theMigratedCapSaysWhereItCameFrom() throws {
        let (vm, _, _, _) = try make(stored: .legacyPreW4)
        #expect(vm.capValueText == "175 bpm")
        #expect(vm.capSubtitle == "From your earlier setup. Confirm or change it — the app never raises it.")
        #expect(vm.recheckSubtitle == "Confirm your HR cap every 8 weeks. Not confirmed yet. JI asks; you decide.")
    }

    @Test func zonesComeFromTheUsersNumberAndEachFloorIsEditable() async throws {
        let (vm, prefs, _, hub) = try make()
        #expect(await vm.setZones(anchor: .maxHr, bpmText: "abc") == false)
        #expect(await vm.setZones(anchor: .maxHr, bpmText: "198"))
        #expect(vm.gateSettings.zones?.floorsBpm == [97, 117, 139, 160, 176])
        #expect(await vm.editZone(5, floorText: "180"))
        #expect(GateSettingsStore(prefs: prefs).load().zones?.floorsBpm == [97, 117, 139, 160, 180])
        #expect(await vm.editZone(3, floorText: "110") == false)         // below Z2's floor: rejected, nothing saved
        #expect(vm.gateSettings.zones?.floorsBpm == [97, 117, 139, 160, 180])
        #expect(hub.puts.last?.zoneFloorsBpm == [97, 117, 139, 160, 180])
    }

    @Test func avoidZone5IsAUserToggleThatNeedsZones() async throws {
        let (vm, prefs, _, _) = try make()
        await vm.setAvoidZone5(true)
        #expect(GateSettingsStore(prefs: prefs).load().avoidZone5 == false)   // no zones yet: stays off
        _ = await vm.setZones(anchor: .lthr, bpmText: "170")
        await vm.setAvoidZone5(true)
        #expect(GateSettingsStore(prefs: prefs).load().zone5FloorBpm == 175)
        await vm.clearZones()
        let s = GateSettingsStore(prefs: prefs).load()
        #expect(s.zones == nil && s.avoidZone5 == false)
    }

    /// W-TGT L3: "Reset rules to recommended" (Targets) puts the caution preset back to Balanced
    /// and never touches the cap (a Limit) — the same promise "Use recommended" made.
    @Test func resetRulesResetsThePresetButNeverTheCap() async throws {
        let (vm, prefs, _, _) = try make()
        try TargetsStore(prefs: prefs).save(.empty)   // after the §5 import
        await vm.setPreset(.cautious)
        _ = await vm.changeHrCap("160")
        await TargetsModel(prefs: prefs).resetRules()
        let s = GateSettingsStore(prefs: prefs).load()
        #expect(s.preset == .balanced)
        #expect(s.hrCapBpm == 160)
    }

    /// W-TGT L3: a Limits write starts from the stored document — a caution rule changed in Targets
    /// after this model loaded is never overwritten with the model's stale preset.
    @Test func aLimitWriteNeverClobbersARuleChangedInTargets() async throws {
        let (vm, prefs, _, _) = try make()
        try TargetsStore(prefs: prefs).save(.empty)
        vm.loadLocal()
        await TargetsModel(prefs: prefs).update { $0.rules[.hrvLowNights] = 3 }
        _ = await vm.changeHrCap("166")
        let doc = TargetsStore(prefs: prefs).load()
        #expect(doc.rules[.hrvLowNights] == 3)
        #expect(doc.limits.hrCapBpm == 166)
    }

    /// Review Focus 3: the phone keeps the value and says so.
    @Test func offlineChangeShowsHubPending() async throws {
        let (vm, prefs, _, _) = try make(hubFails: true)
        _ = await vm.changeHrCap("170")
        #expect(vm.hubPending)
        #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 170)
    }

    /// W-B57-W4 fixer (RF3 label): after a successful PUT the label must go away, and the view
    /// must be told — `hubPending` is observed state, not a computed read of PrefStore.
    @Test func successfulPutClearsTheObservedHubPendingLabel() async throws {
        let (vm, _, _, hub) = try make(hubFails: true)
        _ = await vm.changeHrCap("170")
        #expect(vm.hubPending)
        hub.fail = false
        let changed = ObservedFlag()
        withObservationTracking { _ = vm.hubPending } onChange: { changed.fired = true }
        _ = await vm.changeHrCap("168")
        #expect(hub.puts.last?.hrCapBpm == 168)
        #expect(changed.fired)
        #expect(vm.hubPending == false)
    }
}

// @unchecked: set from the Observation onChange callback, read on the main actor in the test.
final class ObservedFlag: @unchecked Sendable { var fired = false }

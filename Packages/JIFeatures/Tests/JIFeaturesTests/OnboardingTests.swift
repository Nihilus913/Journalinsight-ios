import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// B-57 W4 C3: the four-step first-launch flow. Toby 2026-09-24: the cap, zones and Zone 5 rule are
// the user's; a fresh install has none and nothing is pre-filled.
@MainActor struct OnboardingTests {
    private func make(prefs: PrefStore? = nil) throws -> (OnboardingViewModel, PrefStore, FakeNotificationCenter, GateSettingsHubFake) {
        let p = try prefs ?? PrefStore(db: AppDatabase.inMemory())
        let hub = GateSettingsHubFake(); let center = FakeNotificationCenter()
        let vm = OnboardingViewModel(prefs: p, mirror: GateSettingsMirror(prefs: p, provider: hub),
                                     reminderCenter: center, nightsSoFar: nil, today: { "2026-09-24" })
        return (vm, p, center, hub)
    }

    @Test func freshInstallNeedsOnboardingOnce() async throws {
        let (vm, prefs, _, _) = try make()
        #expect(OnboardingGate.needsOnboarding(prefs))
        await vm.continueTapped(); await vm.continueTapped()          // welcome, baseline
        vm.wantsCap = false
        await vm.continueTapped(); await vm.continueTapped()          // safety, gate
        #expect(vm.finished)
        #expect(!OnboardingGate.needsOnboarding(prefs))
        #expect((try prefs.get(OnboardingGate.key, as: Int.self)) == OnboardingGate.currentVersion)
    }

    @Test func nothingIsPrefilledOnAFreshInstall() throws {
        let (vm, _, _, _) = try make()
        #expect(vm.wantsCap == nil && vm.hrCapText.isEmpty)
        #expect(vm.zoneAnchorText.isEmpty && vm.zonesPreview == nil && vm.avoidZone5 == false)
        #expect(vm.preset == .balanced)
    }

    @Test func finishingSavesCapZonesPresetConfirmationAndSchedulesTheRecheck() async throws {
        let (vm, prefs, center, hub) = try make()
        await vm.continueTapped(); await vm.continueTapped()          // welcome, baseline
        #expect(vm.step == .safety)
        vm.wantsCap = true
        vm.hrCapText = "168"
        vm.zoneAnchor = .maxHr
        vm.zoneAnchorText = "198"
        #expect(vm.zonesPreview == .legacyPreW4)
        vm.avoidZone5 = true
        await vm.continueTapped()
        vm.preset = .cautious
        #expect(vm.primaryTitle == "Use Cautious")
        await vm.continueTapped()
        let s = GateSettingsStore(prefs: prefs).load()
        #expect(s == GateSettings(preset: .cautious, hrCapBpm: 168, avoidZone5: true, zones: .legacyPreW4, hrCapConfirmedOn: "2026-09-24"))
        #expect(hub.puts.last == .init(preset: "cautious", hrCapBpm: 168, avoidZone5: true, zoneFloorsBpm: [97, 117, 139, 160, 176]))
        #expect(await ReminderScheduler(center: center).hrCapCheckDue() == "2026-11-19")
    }

    /// W-TGT L3 (spec §4: "onboarding writes the same document"): after the §5 import the answers
    /// land in the ONE targets document — Limits + the caution rule — and nothing else in it moves.
    @Test func afterTheImportOnboardingWritesTheTargetsDocument() async throws {
        let prefs = try PrefStore(db: AppDatabase.inMemory())
        var doc = TargetsDocument()
        doc.goals.proteinG = 140
        try TargetsStore(prefs: prefs).save(doc)
        let (vm, _, _, _) = try make(prefs: prefs)
        await vm.continueTapped(); await vm.continueTapped()
        vm.wantsCap = true; vm.hrCapText = "166"
        await vm.continueTapped()
        vm.preset = .push
        await vm.continueTapped()
        let after = TargetsStore(prefs: prefs).load()
        #expect(after.limits.hrCapBpm == 166)
        #expect(after.rules[.hrvLowNights] == 3)
        #expect(after.goals.proteinG == 140)
        #expect(after.goals.sleepH == nil)
    }

    /// "No" = no cap: nothing to re-check, and the Zone 5 toggle stays the user's own choice.
    @Test func answeringNoSavesNoCapAndNoRecheck() async throws {
        let (vm, prefs, center, hub) = try make()
        await vm.continueTapped(); await vm.continueTapped()
        vm.wantsCap = false
        vm.hrCapText = "175"                                            // ignored when the answer is No
        await vm.continueTapped(); await vm.continueTapped()
        let s = GateSettingsStore(prefs: prefs).load()
        #expect(s.hrCapBpm == nil && s.hrCapConfirmedOn == "2026-09-24" && s.zones == nil && !s.avoidZone5)
        #expect(hub.puts.last?.hrCapBpm == nil)
        #expect(await ReminderScheduler(center: center).hrCapCheckDue() == nil)
        #expect(center.pending.isEmpty)
    }

    /// Review Focus 2.
    @Test func safetyStepBlocksOnANonNumberOrNoAnswer() async throws {
        let (vm, prefs, _, _) = try make()
        await vm.continueTapped(); await vm.continueTapped()
        await vm.continueTapped()                                       // no answer yet
        #expect(vm.step == .safety && vm.capError == OnboardingCopy.capAnswerMissing)
        vm.wantsCap = true
        for bad in ["17a", "175.0", "", "  "] {
            vm.hrCapText = bad
            await vm.continueTapped()
            #expect(vm.step == .safety)
            #expect(vm.capError == hrCapParseError)
        }
        #expect(GateSettingsStore(prefs: prefs).load() == GateSettings())
        vm.hrCapText = "230"                                            // no range: accepted
        vm.zoneAnchorText = "abc"
        await vm.continueTapped()
        #expect(vm.step == .safety && vm.zoneError == hrCapParseError)  // a typed zone number must be a number
        vm.zoneAnchorText = ""                                          // zones are optional
        await vm.continueTapped()
        #expect(vm.step == .gate && vm.capError == nil && vm.zoneError == nil)
    }

    @Test func avoidZone5NeedsZones() async throws {
        let (vm, prefs, _, _) = try make()
        await vm.continueTapped(); await vm.continueTapped()
        vm.wantsCap = false
        vm.avoidZone5 = true                                            // no zones: not saved as on
        await vm.continueTapped(); await vm.continueTapped()
        #expect(GateSettingsStore(prefs: prefs).load().avoidZone5 == false)
    }

    @Test func skipMarksDoneAndChangesNothing() async throws {
        let (vm, prefs, center, hub) = try make()
        await vm.skip()
        #expect(vm.finished && !OnboardingGate.needsOnboarding(prefs))
        #expect(GateSettingsStore(prefs: prefs).load() == GateSettings())
        #expect(center.pending.isEmpty && hub.puts.isEmpty)
    }

    @Test func backStepsBackButNeverBeforeWelcome() async throws {
        let (vm, _, _, _) = try make()
        vm.back()
        #expect(vm.step == .welcome)
        await vm.continueTapped()
        vm.back()
        #expect(vm.step == .welcome)
    }

    /// Re-run from GateConfig (or Toby's migrated install): starts from what is stored and keeps
    /// hand-edited zone floors when the anchor number is unchanged.
    @Test func rerunStartsFromTheCurrentSettings() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let edited = try #require(HrZones.legacyPreW4.editing(zone: 5, floorBpm: 178))
        try GateSettingsStore(prefs: prefs).save(GateSettings(preset: .push, hrCapBpm: 181, avoidZone5: true, zones: edited,
                                                              hrCapConfirmedOn: "2026-08-01"))
        let (vm, _, _, _) = try make(prefs: prefs)
        #expect(vm.wantsCap == true && vm.hrCapText == "181" && vm.preset == .push)
        #expect(vm.zoneAnchor == .maxHr && vm.zoneAnchorText == "198" && vm.avoidZone5)
        #expect(vm.zonesPreview == edited)
        for _ in 0..<4 { await vm.continueTapped() }
        #expect(GateSettingsStore(prefs: prefs).load().zones == edited)
    }

    @Test func aStoredNoIsRememberedOnARerun() throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        try GateSettingsStore(prefs: prefs).save(GateSettings(hrCapBpm: nil, hrCapConfirmedOn: "2026-09-01"))
        let (vm, _, _, _) = try make(prefs: prefs)
        #expect(vm.wantsCap == false && vm.hrCapText.isEmpty)
    }

    @Test func migratedInstallShowsTobysValues() throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        try GateSettingsStore(prefs: prefs).save(.legacyPreW4)
        let (vm, _, _, _) = try make(prefs: prefs)
        #expect(vm.wantsCap == true && vm.hrCapText == "175" && vm.avoidZone5 && vm.zonesPreview == .legacyPreW4)
    }

    @Test func bumpCapStepsFromTheTypedOrStoredNumberAndNeverInventsOne() throws {
        let (fresh, _, _, _) = try make()
        fresh.bumpCap(+1)
        #expect(fresh.hrCapText.isEmpty)                                // no number anywhere: nothing to step
        fresh.hrCapText = "170"
        fresh.bumpCap(+1)
        #expect(fresh.hrCapText == "171")
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        try GateSettingsStore(prefs: prefs).save(.legacyPreW4)
        let (vm, _, _, _) = try make(prefs: prefs)
        vm.hrCapText = "abc"
        vm.bumpCap(+1)
        #expect(vm.hrCapText == "176")
    }

    @Test func nightsCardNeverInventsACount() throws {
        let (vm, _, _, _) = try make()
        #expect(vm.nightsSoFar == nil)
        #expect(OnboardingCopy.nightsValue(nil) == "—")
        #expect(OnboardingCopy.nightsReason(nil) == JIMissingReason.calibrating.rawValue)
        #expect(OnboardingCopy.nightsValue(.init(have: 9, need: 28)) == "9")
        #expect(OnboardingCopy.nightsReason(.init(have: 9, need: 28)) == nil)
    }

    @Test func medicationIsOnlyWhatTheUserTyped() throws {
        let (vm, prefs, _, _) = try make()
        #expect(vm.medication == nil)
        vm.saveMedication(MedicationEntry(name: "Concerta", dose: "36 mg"))
        #expect(MedicationStore(prefs: prefs).load()?.name == "Concerta")
        vm.saveMedication(MedicationEntry(name: "  "))                  // an unnamed entry clears it
        #expect(vm.medication == nil && MedicationStore(prefs: prefs).load() == nil)
    }

    @Test func stepLabelsAndCopy() throws {
        let (vm, _, _, _) = try make()
        #expect(vm.stepLabel == "Step 1 of 4")
        #expect(OnboardingCopy.welcomeTitle == "Your morning call")
        #expect(OnboardingCopy.safetyDoctorNote == "Have a heart condition? Use the limit your doctor gave you.")
        #expect(OnboardingCopy.capQuestion == "Do you want a heart-rate limit?")
        #expect(OnboardingCopy.avoidZone5Title == "Avoid Zone 5")
        #expect(OnboardingCopy.welcomeRows.map(\.word) == ["Full", "Modified", "Rest"])
    }

    @Test func gateConfigWalkThroughStartsFromTheStoredSettings() throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        try GateSettingsStore(prefs: prefs).save(.legacyPreW4)
        let gc = GateConfigViewModel(prefStore: prefs)
        let vm = gc.makeOnboardingModel()
        #expect(vm.step == .welcome && vm.wantsCap == true && vm.hrCapText == "175")
    }

    @Test func registryRendersTheFourOnboardingBoards() {
        let names = ScreenRegistry.entries.map(\.name)
        for n in ["Onboarding welcome", "Onboarding baseline", "Onboarding safety", "Onboarding gate"] {
            #expect(names.contains(n))
        }
    }
}

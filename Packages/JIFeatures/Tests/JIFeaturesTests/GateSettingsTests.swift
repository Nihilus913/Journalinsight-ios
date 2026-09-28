import Testing
import JICore
import JIPersistence
@testable import JIFeatures

struct GateSettingsTests {
    @Test func presetsAreOneTwoThreeNightsWithBalancedDefault() {
        #expect(GatePreset.allCases.map(\.hrvLowNights) == [1, 2, 3])
        #expect(GateSettings().preset == .balanced)
        #expect(GatePreset.balanced.configSubtitle == "Modified after 2 low HRV nights in a row")
        #expect(GatePreset.cautious.boardDescription == "Modified after one low HRV night. More easy days.")
    }

    /// Toby 2026-09-24: no app default. A new install has no cap, no zones, no Zone 5 rule.
    @Test func aNewInstallHasNoCapNoZonesNoZone5Rule() {
        let s = GateSettings()
        #expect(s.hrCapBpm == nil && !s.hasCap && !s.hrCapChosen)
        #expect(s.zones == nil && s.avoidZone5 == false && s.zone5FloorBpm == nil)
        #expect(s.workoutLimits == .none)
        #expect(s.body == GateSettingsBody(preset: "balanced", hrCapBpm: nil, avoidZone5: false, zoneFloorsBpm: nil))
    }

    @Test func legacyPreW4IsTobysInstall() {
        let s = GateSettings.legacyPreW4
        #expect(s.preset == .balanced && s.hrCapBpm == 175 && s.avoidZone5 && s.zones == .legacyPreW4)
        #expect(s.hrCapConfirmedOn == nil)
        #expect(s.workoutLimits == WorkoutHrLimits(capBpm: 175, zone5FloorBpm: 176))
        #expect(s.body == GateSettingsBody(preset: "balanced", hrCapBpm: 175, avoidZone5: true, zoneFloorsBpm: [97, 117, 139, 160, 176]))
    }

    @Test func avoidZone5NeedsZones() {
        #expect(GateSettings(avoidZone5: true).zone5FloorBpm == nil)
        #expect(GateSettings(avoidZone5: false, zones: .legacyPreW4).zone5FloorBpm == nil)
        #expect(GateSettings(avoidZone5: true, zones: .derived(anchor: .lthr, bpm: 170)).zone5FloorBpm == 175)
    }

    /// Review Focus 2.
    @Test func parseHrCapAcceptsOnlyWholeNumbers() {
        #expect(parseHrCap("175") == 175)
        #expect(parseHrCap(" 168 ") == 168)
        #expect(parseHrCap("0") == 0)           // the user's choice — no range
        #expect(parseHrCap("-5") == -5)
        #expect(parseHrCap("230") == 230)
        for bad in ["", "   ", "175.0", "17a", "1 75", "abc", "١٧٥", "--5", "5-"] { #expect(parseHrCap(bad) == nil, "\(bad)") }
        #expect(hrCapParseError == "Enter a whole number of beats per minute.")
    }

    @Test @MainActor func storeRoundTripsAndIsEmptyWhenNothingIsStored() throws {
        let store = GateSettingsStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
        #expect(store.load() == GateSettings())
        let s = GateSettings(preset: .push, hrCapBpm: 190, avoidZone5: true, zones: .derived(anchor: .lthr, bpm: 170),
                             hrCapConfirmedOn: "2026-09-24")
        try store.save(s)
        #expect(store.load() == s)
        #expect(store.load().hrCapChosen)
    }

    @Test @MainActor func anAnsweredNoCapRoundTrips() throws {
        let store = GateSettingsStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
        let s = GateSettings(hrCapBpm: nil, hrCapConfirmedOn: "2026-09-24")   // the user said "No"
        try store.save(s)
        #expect(store.load() == s)
        #expect(!store.load().hasCap && store.load().hrCapChosen)
    }

    @Test @MainActor func storeToleratesAPartialBlob() throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        try prefs.set(GateSettingsStore.key, ["preset": "cautious"])
        #expect(GateSettingsStore(prefs: prefs).load() == GateSettings(preset: .cautious))
        try prefs.set(GateSettingsStore.key, ["preset": "yolo", "hr_cap_bpm": 160] as [String: GateSettingsBlobValue])
        #expect(GateSettingsStore(prefs: prefs).load() == GateSettings(preset: .balanced, hrCapBpm: 160))
    }

    /// Review Focus 7: only an install that already has pre-W4 data is migrated, and only once.
    @Test @MainActor func migrationOnlyTouchesPreW4Installs() throws {
        let fresh = PrefStore(db: try AppDatabase.inMemory())
        #expect(GateSettingsStore(prefs: fresh).migratePreW4InstallIfNeeded() == false)
        #expect(GateSettingsStore(prefs: fresh).load() == GateSettings())
        try fresh.set("reminders.prefs", ["journal": "on"])            // used later, after W4
        #expect(GateSettingsStore(prefs: fresh).migratePreW4InstallIfNeeded() == false)   // decided once
        #expect(GateSettingsStore(prefs: fresh).load().hrCapBpm == nil)

        let toby = PrefStore(db: try AppDatabase.inMemory())
        try toby.set("reminders.prefs", ["journal": "on"])             // pre-W4 data
        #expect(GateSettingsStore(prefs: toby).migratePreW4InstallIfNeeded())
        #expect(GateSettingsStore(prefs: toby).load() == .legacyPreW4)
        try GateSettingsStore(prefs: toby).save(GateSettings(hrCapBpm: nil, hrCapConfirmedOn: "2026-09-25"))
        #expect(GateSettingsStore(prefs: toby).migratePreW4InstallIfNeeded() == false)    // never re-applied
        #expect(GateSettingsStore(prefs: toby).load().hrCapBpm == nil)
    }

    /// Every pre-W4 marker key is a real PrefStore key some screen writes (not UserDefaults).
    @Test @MainActor func preW4MarkersArePrefStoreKeys() {
        #expect(GateSettingsStore.preW4Keys.contains(RemindersPrefs.prefKey))
        #expect(GateSettingsStore.preW4Keys.contains(todayTileOrderKey))
        #expect(GateSettingsStore.preW4Keys.contains(TargetsStore.morningOverridesKey))
        #expect(GateSettingsStore.preW4Keys.contains(WeeklyPlanStore.prefKey))
        #expect(GateSettingsStore.preW4Keys.contains(GateLaunch.lastAnsweredKey))
        #expect(GateSettingsStore.preW4Keys.contains(KpiSelection.prefKey))
        #expect(!GateSettingsStore.preW4Keys.contains("hk.upload.lastSuccess"))   // UserDefaults, not PrefStore
    }

    @Test func recheckIsEightWeeksAfterConfirmationOrTomorrowWhenOverdue() {
        #expect(GateSettings.recheckWeeks == 8)
        #expect(HrCapRecheck.addDays("2026-09-24", 56) == "2026-11-19")
        #expect(HrCapRecheck.nextDue(confirmedOn: "2026-09-24", today: "2026-09-24") == "2026-11-19")
        #expect(HrCapRecheck.nextDue(confirmedOn: "2026-01-01", today: "2026-09-24") == "2026-09-25")
        #expect(HrCapRecheck.addDays("2026-03-28", 1) == "2026-03-29")   // DST weekend
    }
}

/// Minimal heterogeneous encodable for the partial-blob test.
enum GateSettingsBlobValue: Encodable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    case s(String), i(Int)
    init(stringLiteral v: String) { self = .s(v) }
    init(integerLiteral v: Int) { self = .i(v) }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); switch self { case .s(let v): try c.encode(v); case .i(let v): try c.encode(v) } }
}

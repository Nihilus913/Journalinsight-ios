import Foundation
import Testing
import JICore
@testable import JIPersistence

// W-TGT L1 — TargetsStore + the §5 one-shot import. The golden fixture is the three stores as
// they sit on a used install today (raw PrefStore blobs, the kpi.targets cache and the cached
// /planning/goals mirror). Every number is a test value; the assertion is "same values after".

private enum Fixture {
    static let macros = #"{"kcal":{"basis":{"includes_deficit":{}},"goal_kcal":1617},"protein_g":155,"fat_g":55}"#
    static let gateSettings = #"{"avoid_zone5":true,"hr_cap_bpm":175,"hr_cap_confirmed_on":"2026-09-24","preset":"balanced","zones":{"anchor":"maxHr","anchor_bpm":198,"floors_bpm":[97,117,139,160,176]}}"#
    static let morningOverrides = #"{"RESP_DELTA_AMBER":2.5,"KCAL_TARGET":1800}"#
    static let kpiRules = #"{"acwr|>":{"threshold":1.4}}"#
    static let kpiTargets: [KpiTarget] = [
        KpiTarget(targetId: 1, metric: "acwr", operator: ">", threshold: 1.30, description: "REDUCE: overreaching"),
        KpiTarget(targetId: 2, metric: "avg_kcal_7d", operator: "<", threshold: 1600),
        KpiTarget(targetId: 3, metric: "avg_protein_7d", operator: "<", threshold: 130),
        KpiTarget(targetId: 4, metric: "sleep_score_7d", operator: "<", threshold: 55),
        KpiTarget(targetId: 5, metric: "acwr", operator: "<", threshold: 0.80),
        KpiTarget(targetId: 6, metric: "acwr", operator: "between", threshold: 0.80, thresholdHi: 1.30),
    ]
    static let hubGoals = Goals(weight: WeightGoal(baseKg: 112.4, targetKg: 100, targetDate: "2027-03-01"),
                                strength: [StrengthGoal(exercise: "bench", targetKg: 80)], stepsDaily: 7000,
                                nutrition: NutritionGoal(kcalGoal: 1935))

    static func install(_ db: AppDatabase) throws {
        let prefs = PrefStore(db: db)
        try prefs.set(MacroGoalsStore.key, try JSONDecoder().decode(JSONValue.self, from: Data(macros.utf8)))
        try prefs.set(TargetsStore.gateSettingsKey, try JSONDecoder().decode(JSONValue.self, from: Data(gateSettings.utf8)))
        try prefs.set(TargetsStore.morningOverridesKey, try JSONDecoder().decode(JSONValue.self, from: Data(morningOverrides.utf8)))
        try prefs.set(TargetsStore.kpiRuleOverridesKey, try JSONDecoder().decode(JSONValue.self, from: Data(kpiRules.utf8)))
        try OfflineCache(db: db).put(TargetsStore.kpiTargetsCacheKey, kpiTargets)
        try GoalStore(db: db).saveGoalTargetsMirror(hubGoals)
    }
}

private func sources(_ db: AppDatabase) -> TargetsStore.Sources {
    TargetsStore.Sources(cache: OfflineCache(db: db), goals: GoalStore(db: db), outbox: Outbox(db: db))
}

@Test func goldenImportCarriesTodaysValuesVerbatim() throws {
    let db = try AppDatabase.inMemory()
    try Fixture.install(db)
    let store = TargetsStore(prefs: PrefStore(db: db))
    let result = try #require(store.migrateIfNeeded(sources(db)))
    let d = store.load()
    #expect(d == result.document)

    // Goals
    #expect(d.goals.kcal == KcalGoal(goalKcal: 1617, basis: .includesDeficit))
    #expect(d.goal(.kcal) == 1617 && d.goal(.protein) == 155 && d.goal(.fat) == 55 && d.goal(.carbs) == nil)
    #expect(d.goals.weight == WeightTarget(baseKg: 112.4, targetKg: 100, targetDate: "2027-03-01"))
    #expect(d.goal(.steps) == 7000)
    #expect(d.goals.strength == [StrengthGoal(exercise: "bench", targetKg: 80)])
    #expect(d.goal(.sleep) == nil)
    // Limits
    #expect(d.limits == TargetLimits(hrCapBpm: 175, hrCapConfirmedOn: "2026-09-24",
                                     zones: HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176]),
                                     avoidZone5: true))
    // Rules
    #expect(d.rules[.hrvLowNights] == 2)
    #expect(d.rules[.respDeltaAmber] == 2.5)
    #expect(d.rules[.carbThreeDayFloor] == nil && d.rules[.intervalMinSleep] == nil)
    #expect(d.rules[.loadOver] == 1.30 && d.rules[.loadUnder] == 0.80)
    #expect(d.rules[.loadBandLow] == 0.80 && d.rules[.loadBandHigh] == 1.30)
    #expect(d.rules[.weekKcalFloor] == 1600 && d.rules[.weekProteinFloor] == 130 && d.rules[.weekSleepScoreFloor] == 55)
    // Discarded: the hidden KCAL_TARGET and the preview-only acwr copy.
    #expect(result.discarded.count == 2)

    // Mirrored once through the outbox, the document as the payload.
    let rows = try Outbox(db: db).pending().filter { $0.kind == TargetsDocument.outboxKind }
    #expect(rows.count == 1)
    #expect(try JSONDecoder().decode(TargetsDocument.self, from: rows[0].payload) == d)
    #expect(store.migrationState == .imported)
}

@Test func importRunsExactlyOnce() throws {
    let db = try AppDatabase.inMemory()
    try Fixture.install(db)
    let store = TargetsStore(prefs: PrefStore(db: db))
    #expect(store.migrateIfNeeded(sources(db)) != nil)
    var d = store.load(); d.goals.sleepH = 7; try store.save(d)
    #expect(store.migrateIfNeeded(sources(db)) == nil)
    #expect(store.load().goal(.sleep) == 7)
    #expect(try Outbox(db: db).pending().count == 1)
}

@Test func freshInstallImportsAnEmptyDocument() throws {
    let db = try AppDatabase.inMemory()
    let store = TargetsStore(prefs: PrefStore(db: db))
    #expect(store.loadIfPresent() == nil)
    let r = try #require(store.migrateIfNeeded(sources(db)))
    #expect(r.document == .empty)
    #expect(store.load() == .empty)
    // W-FIX8 T-1: an import with no goals is never mirrored (that body wiped the hub's goals).
    #expect(try Outbox(db: db).pending().isEmpty)
}

// MARK: - W-FIX8 T-1: empty local never overwrites the hub; hub wins over empty local

@Test func goalsEmptyImportWithLimitsIsNotMirrored() throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try prefs.set(TargetsStore.gateSettingsKey, try JSONDecoder().decode(JSONValue.self, from: Data(Fixture.gateSettings.utf8)))
    let store = TargetsStore(prefs: prefs)
    let r = try #require(store.migrateIfNeeded(sources(db)))
    #expect(r.document.goals.isEmpty && r.document.limit(.hrCap) == 175)
    #expect(try Outbox(db: db).pending().isEmpty)
    #expect(store.needsHubSeed)
}

@Test func hubSeedIsNeededOnlyForAGoalsEmptyPhoneAndOnlyOnce() throws {
    let db = try AppDatabase.inMemory()
    let store = TargetsStore(prefs: PrefStore(db: db))
    #expect(store.needsHubSeed)                        // nothing stored yet
    var d = TargetsDocument.empty; d.goals.proteinG = 150
    try store.save(d)
    #expect(!store.needsHubSeed)                       // the phone holds a goal: it is the source
    try store.save(.empty)
    #expect(store.needsHubSeed)
    store.markHubSeeded()
    #expect(!store.needsHubSeed)                       // one-time repair
}

@Test func adoptHubFillsOnlyWhatThePhoneLacksAndQueuesNothing() throws {
    let db = try AppDatabase.inMemory()
    let store = TargetsStore(prefs: PrefStore(db: db))
    var local = TargetsDocument.empty; local.limits.hrCapBpm = 170
    try store.save(local)
    var hub = TargetsDocument.empty
    hub.goals.proteinG = 184.9; hub.goals.strength = [StrengthGoal(exercise: "bench", targetKg: 100)]
    hub.limits.hrCapBpm = 175
    let out = store.adoptHub(hub)
    #expect(out.goals == hub.goals && out.limits.hrCapBpm == 170)
    #expect(store.load() == out)
    #expect(try Outbox(db: db).pending().isEmpty)
}

@Test func theClearIntentIsNeverStored() throws {
    let store = TargetsStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    var d = TargetsDocument.empty; d.clearAllGoals = true
    try store.save(d)
    #expect(store.load().clearAllGoals == false)
}

@Test func legacyKeysStayUntilDeliveredThenGo() throws {
    let db = try AppDatabase.inMemory()
    try Fixture.install(db)
    let prefs = PrefStore(db: db)
    let store = TargetsStore(prefs: prefs)
    let outbox = Outbox(db: db)
    store.migrateIfNeeded(sources(db))
    // Not delivered yet: both readable (rollback = the old keys).
    #expect(!store.finishMigrationIfDelivered(outbox: outbox))
    #expect(try prefs.get(TargetsStore.gateSettingsKey, as: JSONValue.self) != nil)
    #expect(store.migrationState == .imported)
    // Delivered: the outbox row is retired.
    for row in try outbox.pending() { try outbox.markSent(id: row.id) }
    #expect(store.finishMigrationIfDelivered(outbox: outbox))
    #expect(store.migrationState == .delivered)
    for key in TargetsStore.legacyKeys { #expect(try prefs.get(key, as: JSONValue.self) == nil, "\(key)") }
    #expect(try OfflineCache(db: db).get(TargetsStore.kpiTargetsCacheKey, as: [KpiTarget].self) != nil)   // a cache, not a store
    #expect(!store.finishMigrationIfDelivered(outbox: outbox))   // once
}

@Test func unreadableDocumentIsNeverSilentlyReset() throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    try prefs.set(TargetsStore.key, "not a document")
    let store = TargetsStore(prefs: prefs)
    #expect(throws: (any Error).self) { try store.loadThrowing() }
}

// MARK: - MacroGoalsStore reads/writes the document once it exists (accessor swap)

@Test func macroGoalsStoreReadsAndWritesTheDocumentAfterImport() throws {
    let db = try AppDatabase.inMemory()
    try Fixture.install(db)
    let prefs = PrefStore(db: db)
    let store = TargetsStore(prefs: prefs)
    store.migrateIfNeeded(sources(db))
    #expect(try MacroGoalsStore(prefs: prefs).load().proteinG == 155)
    var m = try MacroGoalsStore(prefs: prefs).load(); m.carbsG = 160
    try MacroGoalsStore(prefs: prefs).save(m)
    #expect(store.load().goal(.carbs) == 160)
    #expect(store.load().limit(.hrCap) == 175)   // the rest of the document is untouched
}

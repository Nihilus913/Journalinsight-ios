import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-TGT L1 — the one mirror (outbox kind `targets`) and the accessor swap. Test values only.

/// Test fake; state touched only from the test's MainActor.
final class TargetsHubFake: TargetsProviding, @unchecked Sendable {
    var puts: [TargetsDocument] = []
    var fail: HubError?
    var targetsRoute404 = false

    func targets() async throws -> TargetsDocument { puts.last ?? .empty }
    func putTargets(_ document: TargetsDocument) async throws -> TargetsDocument {
        if targetsRoute404 { throw HubError.http(status: 404, detail: nil) }
        if let fail { throw fail }
        puts.append(document); return document
    }
}

@MainActor private func fixture(_ hub: TargetsHubFake = TargetsHubFake()) throws -> (TargetsMirror, AppDatabase, Outbox, TargetsHubFake) {
    let db = try AppDatabase.inMemory()
    let outbox = Outbox(db: db)
    let drainer = OutboxDrainer(outbox: outbox, hub: hub)
    return (TargetsMirror(prefs: PrefStore(db: db), outbox: outbox, drainer: drainer), db, outbox, hub)
}

private func legacyInstall(_ prefs: PrefStore) throws {
    try MacroGoalsStore(prefs: prefs).save(MacroGoals(kcal: KcalGoal(goalKcal: 1617, basis: .includesDeficit), proteinG: 155))
    try GateSettingsStore(prefs: prefs).save(GateSettings(preset: .cautious, hrCapBpm: 175, avoidZone5: true,
                                                         zones: .legacyPreW4, hrCapConfirmedOn: "2026-09-24"))
}

@Test @MainActor func saveWritesTheStoreAndDeliversOneBody() async throws {
    let (mirror, _, outbox, hub) = try fixture()
    var d = TargetsDocument.empty; d.goals.sleepH = 7
    guard case .delivered(let server) = await mirror.save(d) else { Issue.record("not delivered"); return }
    #expect(server?.goal(.sleep) == 7)
    #expect(hub.puts == [d])
    #expect(mirror.store.load() == d)
    #expect(try outbox.pending().isEmpty)
    #expect(mirror.hubStatusText == nil)
}

@Test @MainActor func offlineSaveStaysQueuedAndOnlyTheNewestIsSentLater() async throws {
    let hub = TargetsHubFake(); hub.fail = .network("down")
    let (mirror, _, outbox, _) = try fixture(hub)
    #expect(await mirror.update { $0.goals.stepsDaily = 7000 } == .queued)
    #expect(await mirror.update { $0.goals.stepsDaily = 8000 } == .queued)
    #expect(mirror.hubStatusText == TargetsMirror.pendingText)
    hub.fail = nil
    #expect(await mirror.pushIfPending())
    #expect(hub.puts.map(\.goals.stepsDaily) == [8000])   // last write wins, never replayed over
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func launchMigrationImportsMirrorsAndThenDropsTheOldKeys() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try legacyInstall(prefs)
    let hub = TargetsHubFake()
    await TargetsMirror.migrateAtLaunch(db: db, hub: hub)
    let d = TargetsStore(prefs: prefs).load()
    #expect(d.goal(.kcal) == 1617 && d.goal(.protein) == 155)
    #expect(d.limit(.hrCap) == 175 && d.limits.zones == .legacyPreW4 && d.limits.avoidZone5)
    #expect(d.rules[.hrvLowNights] == 1)
    #expect(d.goal(.sleep) == nil)
    #expect(hub.puts == [d])
    #expect(TargetsStore(prefs: prefs).migrationState == .delivered)
    for key in TargetsStore.legacyKeys { #expect(try prefs.get(key, as: JSONValue.self) == nil, "\(key)") }
    // Former readers still read the same values, now from the document.
    #expect(try MacroGoalsStore(prefs: prefs).load().targetKcal == 1617)
    #expect(GateSettingsStore(prefs: prefs).load().hrCapBpm == 175)
    #expect(GateSettingsStore(prefs: prefs).load().preset == .cautious)
}

@Test @MainActor func offlineLaunchKeepsTheOldKeysForRollback() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try legacyInstall(prefs)
    await TargetsMirror.migrateAtLaunch(db: db, hub: nil)
    #expect(TargetsStore(prefs: prefs).migrationState == .imported)
    #expect(try prefs.get(TargetsStore.gateSettingsKey, as: JSONValue.self) != nil)
    #expect(try Outbox(db: db).pending().count == 1)
}

@Test @MainActor func gateSettingsStoreWritesTheDocumentAfterImport() throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    let targets = TargetsStore(prefs: prefs)
    var doc = TargetsDocument.empty; doc.goals.proteinG = 155
    try targets.save(doc)
    try GateSettingsStore(prefs: prefs).save(GateSettings(preset: .push, hrCapBpm: nil, avoidZone5: false, zones: nil, hrCapConfirmedOn: "2026-09-28"))
    let after = targets.load()
    #expect(after.limits.hrCapBpm == nil && after.limits.hrCapConfirmedOn == "2026-09-28")
    #expect(after.rules[.hrvLowNights] == 3)
    #expect(after.goal(.protein) == 155)   // Goals untouched
    #expect(try prefs.get(TargetsStore.gateSettingsKey, as: JSONValue.self) == nil)   // no second copy
    #expect(GateSettingsStore(prefs: prefs).load().workoutLimits == .none)
}

@Test @MainActor func gateSettingsMirrorSendsTheDocumentAfterImport() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(.empty)
    let hub = TargetsHubFake()
    let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
    #expect(await mirror.save(GateSettings(preset: .balanced, hrCapBpm: 180)))
    #expect(hub.puts.last?.limits.hrCapBpm == 180)
    // W-FIX10 F10-1: a hub without /planning/targets gets nothing else (the W4
    // `PUT /planning/gate-settings` fallback is gone) — the change stays pending.
    hub.targetsRoute404 = true
    #expect(await mirror.save(GateSettings(preset: .balanced, hrCapBpm: 170)) == false)
    #expect(mirror.hubPending)
}

@Test func presetMapsFromTheCautionRule() {
    #expect(GatePreset(hrvLowNights: nil) == .balanced)
    #expect(GatePreset(hrvLowNights: 1) == .cautious)
    #expect(GatePreset(hrvLowNights: 2) == .balanced)
    #expect(GatePreset(hrvLowNights: 3) == .push)
}

@Test func nutritionSnapshotReadsTheDocument() {
    var d = TargetsDocument.empty
    d.goals.kcal = KcalGoal(goalKcal: 1617, basis: .includesDeficit)
    let s = NutritionGoalsSnapshot(targets: d)
    #expect(s.kcalGoal == 1617)
    #expect(s.goal(for: .protein) == nil)
    #expect(s.caption(for: .protein, value: 100) == MacroGoals.setGoalCopy)
}

/// The import reads the stores by their owners' keys; spelled in JIPersistence, pinned here.
@Test @MainActor func legacyKeysArePinnedToTheirOwners() {
    #expect(TargetsStore.gateSettingsKey == GateSettingsStore.key)
    // W-TGT L3: the override editors are deleted; their RN-era keys are read by the import only.
    #expect(TargetsStore.morningOverridesKey == "config_overrides.morning_gate")
    #expect(TargetsStore.kpiRuleOverridesKey == "config_overrides.kpi_rules")
    #expect(TargetsStore.kpiTargetsCacheKey == localMirrorsKpiTargetsCacheKey)
    #expect(OutboxDrainer.knownKinds.contains(TargetsDocument.outboxKind))
}

/// Recommended rules are exactly the constants the compute port and the hub use today.
@Test func recommendedRulesMatchTheComputePort() {
    let c = MorningGateConfig.default
    #expect(RuleMetric.respDeltaAmber.recommended == c.respDeltaAmber)
    #expect(RuleMetric.carbThreeDayFloor.recommended == Double(c.carb3dWatch))
    #expect(RuleMetric.intervalMinSleep.recommended == c.minSleepH)
    #expect(RuleMetric.hrvLowNights.recommended == Double(GatePreset.balanced.hrvLowNights))
    for rule in RuleMetric.allCases {
        guard let row = rule.kpiTargetRow else { continue }
        let match = defaultKpiRules.first { $0.metric == row.metric && $0.operator == row.op }
        let value = row.hi ? match?.thresholdHi : match?.threshold
        #expect(value == rule.recommended, "\(rule)")
    }
}

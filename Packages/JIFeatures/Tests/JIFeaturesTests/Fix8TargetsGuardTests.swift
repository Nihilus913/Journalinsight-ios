import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-FIX8 T-1 / X-1 — the 2026-09-28 14:51 P0: a first launch built an EMPTY targets document and
// PUT it, wiping the hub's plan.user_goal + user_goal_strength. The app side of the fix:
// hub wins over an empty local document, and no app path PUTs a goals-empty body over hub goals.

/// A hub that behaves like the real one after W-FIX8 (HT `save_targets` + JIHub
/// `HubDataProvider.putTargets`): a goals-empty body without `clearAllGoals` over stored goals is
/// refused with `TargetsWouldClearGoals` and nothing is written. Counts every write it takes.
final class GuardedTargetsHub: TargetsProviding, GateSettingsProviding, @unchecked Sendable {
    var stored: TargetsDocument
    var puts: [TargetsDocument] = []
    var refusals = 0
    var reads = 0
    var gatePuts = 0
    var down = false

    init(_ stored: TargetsDocument) { self.stored = stored }

    func targets() async throws -> TargetsDocument {
        if down { throw HubError.network("down") }
        reads += 1; return stored
    }
    func putTargets(_ document: TargetsDocument) async throws -> TargetsDocument {
        if down { throw HubError.network("down") }
        if document.goals.isEmpty && !document.clearAllGoals && !stored.goals.isEmpty {
            refusals += 1
            throw TargetsWouldClearGoals(server: stored)
        }
        puts.append(document)
        var s = document; s.clearAllGoals = false; stored = s
        return s
    }
    func gateSettings() async throws -> GateSettingsDTO { throw HubError.http(status: 404, detail: nil) }
    func putGateSettings(_ body: GateSettingsBody) async throws -> GateSettingsDTO {
        gatePuts += 1; throw HubError.http(status: 405, detail: nil)
    }
}

/// Toby's hub document as restored from output/backups/pre-052-targets-2026-09-28.json (shape;
/// test values).
private let hubGoals: TargetsDocument = {
    var d = TargetsDocument.empty
    d.goals = TargetGoals(weight: WeightTarget(baseKg: 80.2, targetKg: 75, targetDate: "2026-10-31"),
                          kcal: KcalGoal(goalKcal: 1935, basis: .includesDeficit), proteinG: 184.9, carbsG: 172,
                          fatG: 59.125, stepsDaily: 15000,
                          strength: [StrengthGoal(exercise: "bench", targetKg: 100), StrengthGoal(exercise: "row", targetKg: 100)])
    d.limits = TargetLimits(hrCapBpm: 175, avoidZone5: true)
    return d
}()

@MainActor private func launch(_ db: AppDatabase, hub: GuardedTargetsHub?) async -> TargetsModel {
    let prefs = PrefStore(db: db)
    let outbox = Outbox(db: db)
    TargetsModel.migrateAtLaunch(prefs: prefs, cache: OfflineCache(db: db), goals: GoalStore(db: db), outbox: outbox)
    let mirror = TargetsMirror(prefs: prefs, outbox: outbox, drainer: hub.map { OutboxDrainer(outbox: outbox, hub: $0) })
    let model = TargetsModel(prefs: prefs, mirror: mirror)
    await model.seedFromHub(hub)
    await model.pushIfPending()
    return model
}

// MARK: - Exit: empty local + hub goals → device doc = hub goals, zero PUT

@Test @MainActor func freshInstallAdoptsTheHubGoalsWithZeroPut() async throws {
    let db = try AppDatabase.inMemory()
    let hub = GuardedTargetsHub(hubGoals)
    let model = await launch(db, hub: hub)
    #expect(model.document.goals == hubGoals.goals)
    #expect(model.document.limits == hubGoals.limits)
    #expect(hub.puts.isEmpty && hub.refusals == 0)
    #expect(hub.stored == hubGoals)
    #expect(try Outbox(db: db).pending().isEmpty)
}

@Test @MainActor func theOneShotStaticLaunchAlsoAdoptsWithZeroPut() async throws {
    let db = try AppDatabase.inMemory()
    let hub = GuardedTargetsHub(hubGoals)
    await TargetsMirror.migrateAtLaunch(db: db, hub: hub)
    #expect(TargetsStore(prefs: PrefStore(db: db)).load().goals == hubGoals.goals)
    #expect(hub.puts.isEmpty)
}

@Test @MainActor func tobysPhoneRepairsOnTheNextLaunchOnce() async throws {
    // The phone after 14:51: migrated + delivered, an EMPTY document stored; the hub restored.
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    let store = TargetsStore(prefs: prefs)
    try store.save(.empty)
    try prefs.set(TargetsStore.migrationKey, TargetsStore.MigrationState.delivered)
    let hub = GuardedTargetsHub(hubGoals)
    let model = await launch(db, hub: hub)
    #expect(model.document.goals == hubGoals.goals)
    #expect(hub.puts.isEmpty && hub.reads == 1)
    _ = await launch(db, hub: hub)                     // one-time: no second read
    #expect(hub.reads == 1 && hub.puts.isEmpty)
}

@Test @MainActor func anOfflineLaunchRetriesTheSeedNextTime() async throws {
    let db = try AppDatabase.inMemory()
    let hub = GuardedTargetsHub(hubGoals); hub.down = true
    let first = await launch(db, hub: hub)
    #expect(first.document.goals.isEmpty)
    hub.down = false
    let second = await launch(db, hub: hub)
    #expect(second.document.goals == hubGoals.goals && hub.puts.isEmpty)
}

@Test @MainActor func aPhoneWithGoalsKeepsThemAndNeverReadsTheHub() async throws {
    let db = try AppDatabase.inMemory()
    var mine = TargetsDocument.empty; mine.goals.proteinG = 150
    try TargetsStore(prefs: PrefStore(db: db)).save(mine)
    let hub = GuardedTargetsHub(hubGoals)
    let model = await launch(db, hub: hub)
    #expect(model.document.goals == mine.goals && hub.reads == 0)
}

// MARK: - X-1: no app write path PUTs a goals-empty body over hub goals

@Test @MainActor func aLeftoverGoalsEmptyRowIsRetiredNotSentAndTheHubIsAdopted() async throws {
    // A row queued by the old build (the 14:51 body) still in the outbox at launch.
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(.empty)
    try prefs.set(TargetsStore.hubSeedKey, true)       // seed already spent: the drainer must still hold
    _ = try Outbox(db: db).enqueue(kind: TargetsDocument.outboxKind, payload: TargetsDocument.empty)
    let hub = GuardedTargetsHub(hubGoals)
    let model = await launch(db, hub: hub)
    #expect(hub.puts.isEmpty && hub.refusals == 1)
    #expect(hub.stored == hubGoals)
    #expect(try Outbox(db: db).pending().isEmpty)      // retired, never retried forever
    #expect(model.document.goals == hubGoals.goals)
}

@Test @MainActor func aRuleEditOnAGoalsEmptyPhoneCarriesTheHubGoals() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(.empty)
    try prefs.set(TargetsStore.hubSeedKey, true)
    let hub = GuardedTargetsHub(hubGoals)
    let outbox = Outbox(db: db)
    let model = TargetsModel(prefs: prefs, mirror: TargetsMirror(prefs: prefs, outbox: outbox,
                                                                 drainer: OutboxDrainer(outbox: outbox, hub: hub)))
    await model.update { $0.rules[.weekKcalFloor] = 1500 }
    #expect(hub.refusals == 1)
    #expect(hub.puts.count == 1 && hub.puts.allSatisfy { !$0.goals.isEmpty })
    #expect(hub.stored.goals == hubGoals.goals && hub.stored.rules[.weekKcalFloor] == 1500)
    #expect(model.document.goals == hubGoals.goals && !model.hubPending)
}

@Test @MainActor func removingTheLastGoalIsTheOnlyClearAndSaysSo() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    var one = TargetsDocument.empty; one.goals.proteinG = 150
    try TargetsStore(prefs: prefs).save(one)
    let hub = GuardedTargetsHub(one)
    let outbox = Outbox(db: db)
    let model = TargetsModel(prefs: prefs, mirror: TargetsMirror(prefs: prefs, outbox: outbox,
                                                                 drainer: OutboxDrainer(outbox: outbox, hub: hub)))
    await model.update { $0.goals.proteinG = nil }
    #expect(hub.puts.count == 1 && hub.puts[0].clearAllGoals)
    #expect(hub.stored.goals.isEmpty)
    #expect(!model.document.clearAllGoals)              // the intent is never stored
    // A later edit on the now goals-empty phone is NOT a clear (nothing left to clear on purpose).
    await model.update { $0.rules[.loadOver] = 1.4 }
    #expect(hub.puts.count == 2 && !hub.puts[1].clearAllGoals)
}

@Test @MainActor func theLimitsMirrorNeverWipesHubGoalsEither() async throws {
    // GateSettingsMirror PUTs the whole document directly (onboarding / a Limits change).
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    var local = TargetsDocument.empty; local.limits.hrCapBpm = 170
    try TargetsStore(prefs: prefs).save(local)
    let hub = GuardedTargetsHub(hubGoals)
    let mirror = GateSettingsMirror(prefs: prefs, provider: hub)
    try prefs.set(GateSettingsMirror.pendingKey, true)
    #expect(await mirror.pushIfPending() == false)     // refused, stays pending; hub untouched
    #expect(hub.puts.isEmpty && hub.stored == hubGoals && hub.gatePuts == 0)
    // After the launch seed the phone carries the hub's goals, and the retry goes through.
    await TargetsMirror.seedFromHubIfNeeded(store: TargetsStore(prefs: prefs), hub: hub)
    #expect(await mirror.pushIfPending())
    #expect(hub.puts.count == 1 && hub.puts[0].goals == hubGoals.goals && hub.puts[0].limits.hrCapBpm == 170)
}

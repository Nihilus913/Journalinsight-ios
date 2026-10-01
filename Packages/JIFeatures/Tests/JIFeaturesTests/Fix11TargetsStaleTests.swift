import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-FIX11 H2-01 (S1, bug hunt 2026-10-01): saving ONE target PUT the phone's stale whole document
// and overwrote the hub's newer numbers (74 kg / 12000 steps), even from an unrelated Sleep save.
// A save now sends only the changed keys, applied to a FRESH copy of the hub's document.

/// A hub that holds its own document (`server`); a PUT replaces it. Test values only.
final class StaleHubFake: TargetsProviding, @unchecked Sendable {
    var server: TargetsDocument
    var puts: [TargetsDocument] = []
    var gets = 0
    init(_ server: TargetsDocument) { self.server = server }
    func targets() async throws -> TargetsDocument { gets += 1; return server }
    func putTargets(_ document: TargetsDocument) async throws -> TargetsDocument {
        puts.append(document); server = document; return document
    }
}

private func doc(weightKg: Double?, steps: Int?, sleepH: Double? = nil) -> TargetsDocument {
    var d = TargetsDocument.empty
    d.goals.weight = weightKg.map { WeightTarget(baseKg: 85, targetKg: $0) }
    d.goals.stepsDaily = steps
    d.goals.sleepH = sleepH
    return d
}

@MainActor private func mirror(phone: TargetsDocument, hub: StaleHubFake) throws -> (TargetsMirror, Outbox) {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(phone)
    let outbox = Outbox(db: db)
    return (TargetsMirror(prefs: prefs, outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: hub)), outbox)
}

@Test @MainActor func stepsOnlySaveKeepsTheHubsNewerWeight() async throws {
    let hub = StaleHubFake(doc(weightKg: 74, steps: 12000))
    let (m, outbox) = try mirror(phone: doc(weightKg: 80, steps: 10000), hub: hub)
    _ = await m.update { $0.goals.stepsDaily = 11000 }
    #expect(hub.server.goals.weight?.targetKg == 74)       // the hub's weight survives
    #expect(hub.server.goals.stepsDaily == 11000)          // the one changed key landed
    #expect(m.store.load().goals.weight?.targetKg == 74)   // the phone re-seeds from the hub's answer
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func unrelatedSleepSaveTouchesNoOtherGoal() async throws {
    let hub = StaleHubFake(doc(weightKg: 74, steps: 12000))
    let (m, _) = try mirror(phone: doc(weightKg: 80, steps: 10000), hub: hub)
    _ = await m.update { $0.goals.sleepH = 7.5 }
    #expect(hub.server.goals.weight?.targetKg == 74)
    #expect(hub.server.goals.stepsDaily == 12000)
    #expect(hub.server.goals.sleepH == 7.5)
}

@Test @MainActor func queuedOfflineEditsAllReachAFreshHubCopy() async throws {
    final class Flaky: TargetsProviding, @unchecked Sendable {
        let inner: StaleHubFake; var down = true
        init(_ i: StaleHubFake) { inner = i }
        func targets() async throws -> TargetsDocument {
            if down { throw HubError.network("down") }; return try await inner.targets()
        }
        func putTargets(_ d: TargetsDocument) async throws -> TargetsDocument {
            if down { throw HubError.network("down") }; return try await inner.putTargets(d)
        }
    }
    let hub = StaleHubFake(doc(weightKg: 74, steps: 12000))
    let flaky = Flaky(hub)
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(doc(weightKg: 80, steps: 10000))
    let outbox = Outbox(db: db)
    let m = TargetsMirror(prefs: prefs, outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: flaky))
    #expect(await m.update { $0.goals.sleepH = 7 } == .queued)
    #expect(await m.update { $0.goals.proteinG = 150 } == .queued)
    flaky.down = false
    #expect(await m.pushIfPending())
    #expect(hub.puts.count == 1)                            // still one PUT for the queue
    #expect(hub.server.goals.sleepH == 7 && hub.server.goals.proteinG == 150)
    #expect(hub.server.goals.weight?.targetKg == 74 && hub.server.goals.stepsDaily == 12000)
}

@Test @MainActor func limitsSaveKeepsTheHubsGoals() async throws {
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(doc(weightKg: 80, steps: 10000))
    let hub = StaleHubFake(doc(weightKg: 74, steps: 12000))
    #expect(await GateSettingsMirror(prefs: prefs, provider: hub).save(GateSettings(preset: .balanced, hrCapBpm: 172)))
    #expect(hub.server.limits.hrCapBpm == 172)
    #expect(hub.server.goals.weight?.targetKg == 74 && hub.server.goals.stepsDaily == 12000)
}

@Test func rebaseTakesOnlyTheChangedKeys() {
    let base = doc(weightKg: 80, steps: 10000)
    var next = base; next.goals.stepsDaily = 11000; next.rules[.loadOver] = 1.4
    var hub = doc(weightKg: 74, steps: 12000, sleepH: 8); hub.limits.hrCapBpm = 170
    let out = next.rebased(onto: hub, from: base)
    #expect(out.goals.weight?.targetKg == 74 && out.goals.sleepH == 8 && out.limits.hrCapBpm == 170)
    #expect(out.goals.stepsDaily == 11000 && out.rules[.loadOver] == 1.4)
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W8-L4: the drainer now replays W5b's gate-respond / session-feel rows too (P-hub-watchdog).

@MainActor
private func makeDrainer(outbox: Outbox, weighIn: WeighInFakeProvider? = WeighInFakeProvider(), gate: GateRespondFakeProvider? = GateRespondFakeProvider()) -> OutboxDrainer {
    OutboxDrainer(outbox: outbox, weighIn: weighIn, gateRespond: gate)
}

@Test @MainActor func drainOnceDeliversAQueuedGateRespondRow() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let gate = GateRespondFakeProvider()
    let drainer = makeDrainer(outbox: outbox, gate: gate)
    let id = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .override, overrideReason: "Experiment protocol", windowDays: 14))

    let results = await drainer.drainOnce()

    guard case .success(.gateRespond(let r)) = results[id] else { Issue.record("expected gate-respond success"); return }
    #expect(r.logId == 5)
    #expect(gate.respondCalls.count == 1)
    #expect(gate.respondCalls[0].0 == .override)
    #expect(gate.respondCalls[0].1 == "Experiment protocol")
    #expect(gate.respondCalls[0].2 == 14)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func drainOnceDeliversAQueuedSessionFeelRow() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let gate = GateRespondFakeProvider()
    let drainer = makeDrainer(outbox: outbox, gate: gate)
    let id = try outbox.enqueue(kind: OutboxDrainer.sessionFeelKind, payload: FeelBody(feelScore: 4, notes: "ok", date: "2026-09-18"))

    let results = await drainer.drainOnce()

    guard case .success(.sessionFeel(let r)) = results[id] else { Issue.record("expected feel success"); return }
    #expect(r.feelId == 9)
    #expect(gate.feelCalls.count == 1)
    #expect(gate.feelCalls[0].0 == 4)
    #expect(gate.feelCalls[0].2 == "2026-09-18")
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func gateRowFailureRecordsHubDetailAndStaysPending() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let gate = GateRespondFakeProvider()
    gate.error = .duplicate(detail: "already answered today")
    let drainer = makeDrainer(outbox: outbox, gate: gate)
    let id = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .yes))

    _ = await drainer.drainOnce()

    let rows = try outbox.pending()
    #expect(rows.count == 1)
    #expect(rows[0].id == id)
    #expect(rows[0].attempts == 1)
    #expect(rows[0].lastError == "already answered today")
}

@Test @MainActor func mixedKindsDrainInOneNetworkPass() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider()
    let gate = GateRespondFakeProvider()
    let drainer = makeDrainer(outbox: outbox, weighIn: weighIn, gate: gate)
    let w = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.0, date: nil))
    let g = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .skip))
    let f = try outbox.enqueue(kind: OutboxDrainer.sessionFeelKind, payload: FeelBody(feelScore: 3))
    _ = try outbox.enqueue(kind: "some_other_write", payload: ["x": 1])

    let results = await drainer.drainOnce()

    #expect(results.count == 3)
    #expect(results[w] != nil && results[g] != nil && results[f] != nil)
    #expect(try outbox.pending().count == 1) // the unknown kind is untouched, never dropped
    #expect(try outbox.pending()[0].kind == "some_other_write")
}

@Test @MainActor func aKindWithoutAProviderIsLeftPendingNotDropped() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let drainer = OutboxDrainer(outbox: outbox, weighIn: WeighInFakeProvider(), gateRespond: nil)
    _ = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .yes))

    let results = await drainer.drainOnce()

    #expect(results.isEmpty)
    #expect(try outbox.pending().count == 1)
    #expect(drainer.pendingDeliverableCount() == 0) // not this drainer's to retry
    #expect(drainer.drainableKinds == [OutboxDrainer.weighInKind])
}

@Test @MainActor func w3bConvenienceInitStillHandlesWeighInOnly() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let drainer = OutboxDrainer(outbox: outbox, provider: WeighInFakeProvider())
    #expect(drainer.drainableKinds == [OutboxDrainer.weighInKind])
}

@Test @MainActor func pendingDeliverableCountCountsOnlyDrainableKinds() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let drainer = makeDrainer(outbox: outbox)
    _ = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.0, date: nil))
    _ = try outbox.enqueue(kind: OutboxDrainer.sessionFeelKind, payload: FeelBody(feelScore: 3))
    _ = try outbox.enqueue(kind: "some_other_write", payload: ["x": 1])
    #expect(drainer.pendingDeliverableCount() == 2)
}

// MARK: - W-B54 (B54-1): lift edits are outbox rows of kind `exercise_patch`

nonisolated final class ExercisePatchFakeProvider: ExercisePatchProviding, @unchecked Sendable {
    var error: Error?
    var calls: [(Int, ExerciseUpdate)] = []
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        calls.append((exerciseId, patch))
        if let error { throw error }
        return ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }
}

private func b54Store() -> StrengthStateStore {
    StrengthStateStore(defaults: UserDefaults(suiteName: "b54.drainer.\(UUID().uuidString)"))
}

@Test @MainActor func exercisePatchKindIsKnownAndDrainableWithAProvider() {
    #expect(OutboxDrainer.exercisePatchKind == "exercise_patch")
    #expect(OutboxDrainer.knownKinds.contains("exercise_patch"))
    let outbox = Outbox(db: try! AppDatabase.inMemory())
    #expect(OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: ExercisePatchFakeProvider(), strengthStore: b54Store())
        .drainableKinds.contains("exercise_patch"))
    #expect(!OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil).drainableKinds.contains("exercise_patch"))
}

@Test @MainActor func aQueuedExercisePatchIsSentAndTheLocalRowMarkedSynced() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = ExercisePatchFakeProvider()
    let store = b54Store()
    let patch = ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5, sets: 3, repsTarget: 8)
    store.saveLocal(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: patch)
    let id = try outbox.enqueue(kind: OutboxDrainer.exercisePatchKind, payload: ExercisePatchBody(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: patch))
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: hub, strengthStore: store)

    let results = await drainer.drainOnce()

    guard case .success(.exercisePatch(let r)) = results[id] else { Issue.record("expected exercise-patch success, got \(String(describing: results[id]))"); return }
    #expect(r == ExerciseUpdateResult(exerciseId: 19, updated: true))
    #expect(hub.calls.count == 1)
    #expect(hub.calls.first?.0 == 19)
    #expect(hub.calls.first?.1 == patch)
    #expect(try outbox.pending().isEmpty)
    #expect(store.getLocal(exerciseId: 19)?.synced == true)
}

@Test @MainActor func anUnreachableHubLeavesTheExercisePatchQueued() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = ExercisePatchFakeProvider()
    hub.error = HubError.network("offline")
    let store = b54Store()
    let patch = ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5)
    store.saveLocal(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: patch)
    let id = try outbox.enqueue(kind: OutboxDrainer.exercisePatchKind, payload: ExercisePatchBody(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: patch))
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: hub, strengthStore: store)

    _ = await drainer.drainOnce()

    let rows = try outbox.pending()
    #expect(rows.map(\.id) == [id])
    #expect(rows.first?.attempts == 1)
    #expect(store.getLocal(exerciseId: 19)?.synced == false)
}

@Test @MainActor func aHubRefusalRetiresTheExercisePatch() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = ExercisePatchFakeProvider()
    hub.error = HubError.http(status: 422, detail: "current_weight_kg must be >= 0")
    let id = try outbox.enqueue(kind: OutboxDrainer.exercisePatchKind, payload: ExercisePatchBody(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: -1, progressionStepKg: 2.5)))
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: hub, strengthStore: b54Store())

    let results = await drainer.drainOnce()

    guard case .failure? = results[id] else { Issue.record("a refusal must be reported as a failure"); return }
    #expect(try outbox.pending().isEmpty) // retired: retrying a 4xx forever would be a lie
}

@Test @MainActor func severalEditsOfOneLiftSendOnlyTheNewestAndRetireAll() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = ExercisePatchFakeProvider()
    let store = b54Store()
    let older = try outbox.enqueue(kind: OutboxDrainer.exercisePatchKind, payload: ExercisePatchBody(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5)))
    let newer = try outbox.enqueue(kind: OutboxDrainer.exercisePatchKind, payload: ExercisePatchBody(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: 55, progressionStepKg: 2.5)))
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: hub, strengthStore: store)

    let results = await drainer.drainOnce()

    #expect(hub.calls.map(\.1.currentWeightKg) == [55]) // last edit wins on the hub
    guard case .success(.exercisePatch)? = results[newer] else { Issue.record("newest row must be delivered"); return }
    _ = older
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func legacyUnsyncedLiftEditsAreEnqueuedOnceAndDelivered() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = ExercisePatchFakeProvider()
    let store = b54Store()
    // An older build saved this offline edit locally and never replayed it.
    store.saveLocal(exerciseId: 21, exerciseName: "Lat Pulldown", patch: ExerciseUpdate(currentWeightKg: 45, progressionStepKg: 2.5, sets: 3, repsTarget: 10))
    store.saveLocal(exerciseId: 19, exerciseName: "Barbell Bench Press", patch: ExerciseUpdate(currentWeightKg: 50, progressionStepKg: 2.5))
    store.markSynced(exerciseId: 19)
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, exercisePatch: hub, strengthStore: store)

    _ = await drainer.drainOnce()

    #expect(hub.calls.map(\.0) == [21])
    #expect(hub.calls.first?.1 == ExerciseUpdate(currentWeightKg: 45, progressionStepKg: 2.5, sets: 3, repsTarget: 10))
    #expect(store.listUnsynced().isEmpty)
    #expect(try outbox.pending().isEmpty)

    // Once per install: a later unsynced row is the outbox's business, not a second hand-over.
    store.saveLocal(exerciseId: 22, exerciseName: "Row", patch: ExerciseUpdate(currentWeightKg: 40, progressionStepKg: 2.5))
    _ = await drainer.drainOnce()
    #expect(hub.calls.count == 1)
}

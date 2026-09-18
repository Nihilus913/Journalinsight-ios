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

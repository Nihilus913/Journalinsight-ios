import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-FIX10 F10-1 (audit 03-F1): `goals_put` rows (the removed `PUT /planning/goals`, a 405 on
// every replay) are retired unsent by a drainer that can deliver the targets document — they are
// never sent to the hub again, and never count as pending goals work.

@Test @MainActor func aLegacyGoalsPutIsRetiredUnsentNeverReplayed() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = TargetsHubFake()
    let drainer = OutboxDrainer(outbox: outbox, hub: hub)
    let id = try outbox.enqueue(kind: OutboxDrainer.legacyGoalsKind, payload: GoalsUpdate(stepsDaily: 12000))
    #expect(drainer.pendingDeliverableCount() == 1)

    let results = await drainer.drainOnce()

    #expect(results[id] == nil)            // nothing was attempted against the hub
    #expect(hub.puts.isEmpty)
    #expect(try outbox.pending().isEmpty)  // retired, not left to fail forever
}

@Test @MainActor func aLegacyGoalsPutStaysWithoutATargetsProvider() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil)
    _ = try outbox.enqueue(kind: OutboxDrainer.legacyGoalsKind, payload: GoalsUpdate(stepsDaily: 12000))
    _ = await drainer.drainOnce()
    #expect(try outbox.pending().count == 1)
    #expect(!drainer.drainableKinds.contains(OutboxDrainer.legacyGoalsKind))
}

@Test @MainActor func aLegacyGoalsPutIsNotPendingGoalsWork() throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    #expect(OutboxDrainer.knownKinds.contains(OutboxDrainer.legacyGoalsKind))
    _ = try outbox.enqueue(kind: OutboxDrainer.legacyGoalsKind, payload: GoalsUpdate(stepsDaily: 12000))
    #expect(!GoalsSetupViewModel.goalsPending(in: outbox))
    _ = try outbox.enqueue(kind: TargetsDocument.outboxKind, payload: TargetsDocument.empty)
    #expect(GoalsSetupViewModel.goalsPending(in: outbox))
}

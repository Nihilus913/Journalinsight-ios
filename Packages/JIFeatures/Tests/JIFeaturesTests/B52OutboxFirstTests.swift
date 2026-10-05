import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// B-52 p1 (a)/(c): the OutboxFirst helper round-trips a fake kind — hub down → row queued,
/// hub up → row drained — through a registered handler, plus coalescing, permanent rejection and
/// the reachability-regain trigger.
private struct FakeBody: Codable, Sendable, Equatable { var target: String; var value: Int }

@MainActor
private final class FakeHub {
    var up = false
    var rejectWith: HubError?
    var delivered: [FakeBody] = []
    func write(_ body: FakeBody) async throws {
        if let rejectWith { throw rejectWith }
        guard up else { throw HubError.network("The Internet connection appears to be offline.") }
        delivered.append(body)
    }
}

@MainActor
private func harness(coalesce: Bool = false) throws -> (Outbox, OutboxDrainer, FakeHub, OutboxFirst) {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = FakeHub()
    let registry = OutboxFirstRegistry()
    let byTarget: (@Sendable (FakeBody) -> String)? = coalesce ? { @Sendable (b: FakeBody) -> String in b.target } : nil
    let send: @MainActor @Sendable (FakeBody) async throws -> Void = { @MainActor (b: FakeBody) async throws in try await hub.write(b) }
    let handler = OutboxReplayHandler.make(kind: "fake_kind", payload: FakeBody.self, coalesce: byTarget, send: send)
    registry.register(handler)
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, registry: registry)
    return (outbox, drainer, hub, OutboxFirst(outbox: outbox, drainer: drainer))
}

@MainActor @Suite struct B52OutboxFirstTests {
    @Test func b52_outboxFirstQueuesWhileHubDownAndDrainsWhenUp() async throws {
        let (outbox, drainer, hub, helper) = try harness()
        let outcome = await helper.submit(kind: "fake_kind", payload: FakeBody(target: "a", value: 1))
        guard case .queued(let reason) = outcome else { Issue.record("expected queued, got \(outcome)"); return }
        #expect(reason.contains("offline"))
        #expect(try outbox.pending().count == 1)
        #expect(try outbox.pending().first?.attempts == 1)
        #expect(drainer.drainableKinds.contains("fake_kind"))
        #expect(drainer.pendingDeliverableCount() == 1)

        hub.up = true
        let results = await drainer.drainOnce()
        #expect(results.values.contains { if case .success(.registered(kind: "fake_kind")) = $0 { true } else { false } })
        #expect(try outbox.pending().isEmpty)
        #expect(hub.delivered == [FakeBody(target: "a", value: 1)])
    }

    @Test func b52_outboxFirstDeliversInTheSameBeatWhenHubUp() async throws {
        let (outbox, _, hub, helper) = try harness()
        hub.up = true
        #expect(await helper.submit(kind: "fake_kind", payload: FakeBody(target: "a", value: 2)) == .delivered)
        #expect(try outbox.pending().isEmpty)
        #expect(hub.delivered.count == 1)
    }

    @Test func b52_coalescedKindSendsOnlyTheNewestPerKey() async throws {
        let (outbox, drainer, hub, helper) = try harness(coalesce: true)
        _ = await helper.submit(kind: "fake_kind", payload: FakeBody(target: "a", value: 1))
        _ = await helper.submit(kind: "fake_kind", payload: FakeBody(target: "a", value: 2))
        _ = await helper.submit(kind: "fake_kind", payload: FakeBody(target: "b", value: 9))
        hub.up = true
        await drainer.drainOnce()
        #expect(try outbox.pending().isEmpty)
        #expect(hub.delivered == [FakeBody(target: "a", value: 2), FakeBody(target: "b", value: 9)])
    }

    @Test func b52_permanentRejectionRetiresTheRow() async throws {
        let (outbox, _, hub, helper) = try harness()
        hub.rejectWith = .http(status: 422, detail: "bad value")
        #expect(await helper.submit(kind: "fake_kind", payload: FakeBody(target: "a", value: -1)) == .rejected(reason: "bad value"))
        #expect(try outbox.pending().isEmpty)
    }

    @Test func b52_unregisteredKindIsLeftUntouched() async throws {
        let (outbox, drainer, _, _) = try harness()
        try outbox.enqueue(kind: "someone_elses_kind", payload: FakeBody(target: "x", value: 0))
        await drainer.drainOnce()
        #expect(try outbox.pending().count == 1)
        #expect(try outbox.pending().first?.attempts == 0)
    }

    @Test func b52_reachabilityRegainFiresOnlyOnFalseToTrueEdge() async throws {
        let (outbox, drainer, hub, helper) = try harness()
        _ = await helper.submit(kind: "fake_kind", payload: FakeBody(target: "a", value: 1))
        let trigger = ReachabilityDrainTrigger(onRegain: { await drainer.drainOnce() })
        #expect(await trigger.observe(satisfied: true) == false)    // first observation only seeds
        #expect(await trigger.observe(satisfied: false) == false)
        hub.up = true
        #expect(await trigger.observe(satisfied: true) == true)     // regain → drained
        #expect(trigger.regainCount == 1)
        #expect(try outbox.pending().isEmpty)
        #expect(await trigger.observe(satisfied: true) == false)
    }

    @Test func b52_schedulerDrainNowDeliversQueuedRegisteredRow() async throws {
        let (outbox, drainer, hub, helper) = try harness()
        _ = await helper.submit(kind: "fake_kind", payload: FakeBody(target: "a", value: 1))
        hub.up = true
        let scheduler = OutboxRetryScheduler(drainerSource: { drainer }, background: nil)
        #expect(await scheduler.drainNow() == 1)
        #expect(try outbox.pending().isEmpty)
    }
}

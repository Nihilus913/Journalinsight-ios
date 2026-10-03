import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// A stand-in for the hub's strength-log routes (HT `app/planning/strength_log.py`): idempotent on
/// client ids exactly like the real tables' UNIQUE columns. `online = false` = every call throws a
/// network error. Shared by the W-B38-A logger / history tests.
nonisolated final class StrengthFakeHub: TrainingProviding, @unchecked Sendable { // @unchecked: tests drive it from one actor
    var online = true
    var exerciseRows: [Exercise] = []
    var days: [String: TrainingDayDetail] = [:]
    var sessions: [String: StrengthSessionOut] = [:]   // by client_id
    var sets: [String: StrengthSetOut] = [:]            // by set client_id
    var setOrder: [String] = []
    var completes: [(String, StrengthSessionComplete)] = []
    var calls: [String] = []
    var lastSetsAnswer: [String: [StrengthSetOut]] = [:]

    private func gate(_ call: String) throws {
        calls.append(call)
        if !online { throw HubError.network("The Internet connection appears to be offline.") }
    }

    func trainingDay(date: String) async throws -> TrainingDayDetail {
        try gate("GET day \(date)")
        return days[date] ?? TrainingDayDetail(date: date, activities: [], exerciseSets: [])
    }
    func exercises() async throws -> [Exercise] { try gate("GET exercises"); return exerciseRows }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }

    func createStrengthSession(_ body: StrengthSessionCreate) async throws -> StrengthSessionOut {
        try gate("POST session \(body.clientId)")
        if sessions[body.clientId] == nil {
            sessions[body.clientId] = StrengthSessionOut(sessionLogId: sessions.count + 1, clientId: body.clientId,
                                                         sessionId: body.sessionId, date: body.date, startedAt: body.startedAt)
        }
        return sessions[body.clientId]!
    }
    func logStrengthSet(session: String, _ body: StrengthSetIn) async throws -> StrengthWriteAck {
        try gate("POST set \(body.clientId)")
        guard sessions[session] != nil else { throw HubError.http(status: 404, detail: "Strength session not found") }
        if sets[body.clientId] == nil { setOrder.append(body.clientId) }
        sets[body.clientId] = sets[body.clientId] ?? out(session, body)
        return StrengthWriteAck(clientId: body.clientId)
    }
    func updateStrengthSet(session: String, clientId: String, _ body: StrengthSetIn) async throws -> StrengthWriteAck {
        try gate("PUT set \(clientId)")
        guard sets[clientId] != nil else { throw HubError.http(status: 404, detail: "Set not found") }
        sets[clientId] = out(session, body)
        return StrengthWriteAck(clientId: clientId)
    }
    func deleteStrengthSet(session: String, clientId: String) async throws {
        try gate("DELETE set \(clientId)")
        sets[clientId] = nil; setOrder.removeAll { $0 == clientId }
    }
    func completeStrengthSession(session: String, _ body: StrengthSessionComplete) async throws -> StrengthSessionOut {
        try gate("POST complete \(session)")
        completes.append((session, body))
        sessions[session]?.endedAt = body.endedAt
        return sessions[session] ?? StrengthSessionOut(sessionLogId: nil, clientId: session, date: nil, startedAt: nil)
    }
    func strengthSessions(from: String, to: String) async throws -> [StrengthSessionOut] {
        try gate("GET sessions")
        return sessions.values.filter { ($0.date ?? "") >= from && ($0.date ?? "") <= to }.map { s in
            var s = s
            s.sets = setOrder.compactMap { sets[$0] }.filter { $0.sessionLogId == s.sessionLogId }
            return s
        }
    }
    func strengthLastSets(exerciseKey: String) async throws -> [StrengthSetOut] {
        try gate("GET last-sets \(exerciseKey)")
        return lastSetsAnswer[exerciseKey] ?? []
    }

    private func out(_ session: String, _ b: StrengthSetIn) -> StrengthSetOut { Self.makeOut(b, id: sessions[session]?.sessionLogId) }
    private static func makeOut(_ b: StrengthSetIn, id: Int?) -> StrengthSetOut {
        StrengthSetOut(clientId: b.clientId, sessionLogId: id, exerciseKey: b.exerciseKey, exerciseId: b.exerciseId, setIndex: b.setIndex,
                       kind: b.kind, reps: b.reps, weightKg: b.weightKg, durationS: b.durationS, rpe: b.rpe, performedAt: b.performedAt)
    }
}

private func setBody(_ id: String, _ idx: Int, kg: Double = 50) -> StrengthSetIn {
    StrengthSetIn(clientId: id, exerciseKey: "Barbell Bench Press", exerciseId: 7, setIndex: idx, kind: "reps",
                  reps: 8, weightKg: kg, durationS: nil, rpe: nil, performedAt: "2026-10-03T07:0\(idx):00Z")
}

@MainActor @Suite struct StrengthOutboxTests {
    let hub = StrengthFakeHub()
    let outbox: Outbox
    let queue: StrengthOutbox
    init() throws {
        outbox = Outbox(db: try AppDatabase.inMemory())
        queue = StrengthOutbox(outbox: outbox, provider: hub)
    }

    @Test func testOfflineSetsQueueAndDrainInOrder() async throws {
        hub.online = false
        queue.enqueue(.createSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: 1)))
        for i in 1...3 { queue.enqueue(.logSet(session: "S", setBody("set-\(i)", i))) }
        let offline = await queue.drainOnce()
        #expect(offline.count == 1)                       // stopped at the first failure: order kept
        #expect(queue.pendingCount == 4)
        #expect(hub.sessions.isEmpty && hub.sets.isEmpty)

        hub.online = true
        let online = await queue.drainOnce()
        #expect(online.values.allSatisfy { $0 == .delivered } && online.count == 4)
        #expect(queue.pendingCount == 0)
        #expect(hub.setOrder == ["set-1", "set-2", "set-3"])
        #expect(Array(hub.calls.suffix(4)) == ["POST session S", "POST set set-1", "POST set set-2", "POST set set-3"])
    }

    @Test func testReplaySameClientIdIsIdempotent() async throws {
        queue.enqueue(.createSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: nil)))
        queue.enqueue(.logSet(session: "S", setBody("set-1", 1)))
        queue.enqueue(.logSet(session: "S", setBody("set-1", 1)))   // double tap / re-enqueue
        #expect(queue.pendingCount == 2)                              // coalesced on the phone
        await queue.drainOnce()
        // A crash after the hub answered but before the row retired replays the same write:
        // the hub (UNIQUE client_id) still holds one row.
        _ = try await hub.logStrengthSet(session: "S", setBody("set-1", 1))
        _ = try await hub.createStrengthSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: nil))
        #expect(hub.sets.count == 1 && hub.sessions.count == 1)
    }

    @Test func editOfAQueuedSetRewritesItsLogAndDeleteDropsIt() async throws {
        hub.online = false
        queue.enqueue(.createSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: nil)))
        queue.enqueue(.logSet(session: "S", setBody("a", 1)))
        queue.enqueue(.logSet(session: "S", setBody("b", 2)))
        queue.enqueue(.updateSet(session: "S", setBody("a", 1, kg: 55)))
        queue.enqueue(.deleteSet(session: "S", clientId: "b"))
        hub.online = true
        await queue.drainOnce()
        #expect(hub.setOrder == ["a"])
        #expect(hub.sets["a"]?.weightKg == 55)
        #expect(!hub.calls.contains { $0.hasPrefix("PUT") || $0.hasPrefix("DELETE") })
    }

    @Test func editAndDeleteOfADeliveredSetGoToTheKeyedRoutes() async throws {
        queue.enqueue(.createSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: nil)))
        queue.enqueue(.logSet(session: "S", setBody("a", 1)))
        await queue.drainOnce()
        queue.enqueue(.updateSet(session: "S", setBody("a", 1, kg: 60)))
        await queue.drainOnce()
        #expect(hub.sets["a"]?.weightKg == 60)
        queue.enqueue(.deleteSet(session: "S", clientId: "a"))
        await queue.drainOnce()
        #expect(hub.sets.isEmpty)
    }

    @Test func aRefusedRowIsRetiredAndTheRestStillDrain() async throws {
        queue.enqueue(.logSet(session: "missing", setBody("x", 1)))   // 404: no such session
        queue.enqueue(.createSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: nil)))
        let r = await queue.drainOnce()
        #expect(r.values.contains(.refused("Strength session not found")))
        #expect(queue.pendingCount == 0)
        #expect(hub.sessions["S"] != nil)
    }

    @Test func providerWithoutTheRoutesKeepsEverythingQueued() async throws {
        let bare = StrengthOutbox(outbox: outbox, provider: PlanWeekdayFakeProvider())
        bare.enqueue(.createSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: nil)))
        let r = await bare.drainOnce()
        #expect(r.values.first == .queued("This hub has no strength log yet — kept on the phone."))
        #expect(bare.pendingCount == 1)
    }
}

/// W-B38-A fix (verifier gap): strength rows queued offline must go out when the hub is back even
/// if the Log sets screen is never reopened — the app-wide `OutboxDrainer` (watchdog / retry
/// scheduler / BG refresh) replays them through the strength lane.
@MainActor @Suite struct StrengthOutboxAppDrainTests {
    let hub = StrengthFakeHub()
    let outbox: Outbox
    init() throws { outbox = Outbox(db: try AppDatabase.inMemory()) }

    private func queueOfflineSession(_ queue: StrengthOutbox) async {
        hub.online = false
        queue.enqueue(.createSession(StrengthSessionCreate(clientId: "S", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: 1)))
        for i in 1...2 { queue.enqueue(.logSet(session: "S", setBody("set-\(i)", i))) }
        queue.enqueue(.complete(session: "S", StrengthSessionComplete(endedAt: "2026-10-03T08:00:00Z", advance: [])))
        await queue.drainOnce()
    }

    @Test func appDrainerReplaysStrengthRowsWithoutTheScreen() async throws {
        await queueOfflineSession(StrengthOutbox(outbox: outbox, provider: hub))   // the screen, then gone
        let drainer = OutboxDrainer(outbox: outbox, hub: hub)
        #expect(drainer.drainableKinds.contains(StrengthOutbox.kind))
        #expect(drainer.pendingDeliverableCount() == 4)                          // the scheduler keeps retrying
        hub.online = true
        await drainer.drainOnForeground()
        #expect(drainer.pendingDeliverableCount() == 0)
        #expect(hub.setOrder == ["set-1", "set-2"])
        #expect(hub.completes.count == 1)
    }

    @Test func appDrainerWithoutTrainingProviderLeavesStrengthRowsAlone() async throws {
        await queueOfflineSession(StrengthOutbox(outbox: outbox, provider: hub))
        let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil)
        #expect(!drainer.drainableKinds.contains(StrengthOutbox.kind))
        hub.online = true
        await drainer.drainOnce()
        #expect(StrengthOutbox(outbox: outbox, provider: hub).pendingCount == 4)
    }

    @Test func screenAndAppDrainOverlappingNeverSendTwice() async throws {
        let screen = StrengthOutbox(outbox: outbox, provider: hub)
        await queueOfflineSession(screen)
        hub.online = true
        let drainer = OutboxDrainer(outbox: outbox, hub: hub)
        async let a = screen.drainOnce()
        async let b = drainer.drainOnce()
        _ = await (a, b)
        #expect(hub.completes.count == 1)                                        // one advance, not two
        #expect(hub.calls.filter { $0.hasPrefix("POST set set-1") }.count == 1)
        #expect(screen.pendingCount == 0)
    }
}

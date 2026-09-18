import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W8-L4 (P-hub-watchdog): foreground backoff loop + BGAppRefreshTask, with the OS scheduler faked.

/// Records what the scheduler asked of the OS and lets a test "launch" the registered BG task.
nonisolated final class FakeBackgroundScheduler: BackgroundRefreshScheduling, @unchecked Sendable { // @unchecked: test double, touched from one test task at a time
    var permitted = true
    var registered: [String: @Sendable () async -> Bool] = [:]
    var submissions: [(String, Date?)] = []
    var cancellations: [String] = []

    func register(identifier: String, handler: @escaping @Sendable () async -> Bool) -> Bool {
        guard permitted else { return false }
        registered[identifier] = handler
        return true
    }
    func submitRefresh(identifier: String, earliestBeginDate: Date?) throws { submissions.append((identifier, earliestBeginDate)) }
    func cancelRefresh(identifier: String) { cancellations.append(identifier) }

    /// Simulates the OS launching the BG refresh.
    func fire(_ identifier: String = OutboxRetryScheduler.refreshTaskIdentifier) async -> Bool? {
        guard let handler = registered[identifier] else { return nil }
        return await handler()
    }
}

/// Records requested sleeps instead of waiting; throws once `limit` sleeps were requested so a
/// `startForeground()` loop ends deterministically.
nonisolated final class RecordingSleep: @unchecked Sendable { // @unchecked: test double, appended from the loop task only
    var requested: [Duration] = []
    let limit: Int
    init(limit: Int = .max) { self.limit = limit }
    func sleep(_ d: Duration) async throws {
        requested.append(d)
        if requested.count >= limit { throw CancellationError() }
        await Task.yield()
    }
}

@MainActor
private func makeScheduler(
    outbox: Outbox, weighIn: WeighInFakeProvider, gate: GateRespondFakeProvider,
    background: FakeBackgroundScheduler?, sleep: RecordingSleep = RecordingSleep(),
    now: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> (OutboxRetryScheduler, OutboxDrainer) {
    let drainer = OutboxDrainer(outbox: outbox, weighIn: weighIn, gateRespond: gate)
    let scheduler = OutboxRetryScheduler(drainer: drainer, background: background, sleep: { try await sleep.sleep($0) }, now: { now })
    return (scheduler, drainer)
}

// MARK: - Backoff (pure)

@Test func backoffDoublesFromBaseAndCaps() {
    let b = OutboxRetryScheduler.Backoff.default
    #expect(b.delay(attempt: 0) == .seconds(30))
    #expect(b.delay(attempt: 1) == .seconds(30))
    #expect(b.delay(attempt: 2) == .seconds(60))
    #expect(b.delay(attempt: 3) == .seconds(120))
    #expect(b.delay(attempt: 6) == .seconds(15 * 60)) // 30·2^5 = 960 > 900 → capped
    #expect(b.delay(attempt: 40) == .seconds(15 * 60)) // never overflows past the cap
}

// MARK: - Foreground: offline weigh-in AND gate-respond rows drain on the next foreground

@Test @MainActor func foregroundTickDrainsBothKindsOnceTheHubIsBack() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider(); let gate = GateRespondFakeProvider()
    weighIn.error = .network("offline"); gate.error = .network("offline")
    let (scheduler, _) = makeScheduler(outbox: outbox, weighIn: weighIn, gate: gate, background: nil)
    _ = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.0, date: "2026-09-18"))
    _ = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .yes))
    _ = try outbox.enqueue(kind: OutboxDrainer.sessionFeelKind, payload: FeelBody(feelScore: 4))

    // Still offline: nothing delivered, backoff engages.
    let d1 = await scheduler.foregroundTick()
    #expect(try outbox.pending().count == 3)
    #expect(scheduler.consecutiveIncompletePasses == 1)
    #expect(d1 == .seconds(30))
    let d2 = await scheduler.foregroundTick()
    #expect(scheduler.consecutiveIncompletePasses == 2)
    #expect(d2 == .seconds(60))

    // Hub back (next foreground): one pass delivers all three, streak resets, loop idles.
    weighIn.error = nil; gate.error = nil
    let d3 = await scheduler.foregroundTick()
    #expect(try outbox.pending().isEmpty)
    #expect(gate.respondCalls.count == 3) // two offline attempts (recorded by the fake) + the one that landed
    #expect(gate.feelCalls.count == 3)
    #expect(scheduler.consecutiveIncompletePasses == 0)
    #expect(d3 == scheduler.idleInterval)
}

@Test @MainActor func foregroundLoopSleepsTheBackoffLadderWhileRowsStayPending() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider(); let gate = GateRespondFakeProvider()
    weighIn.error = .network("offline")
    let sleep = RecordingSleep(limit: 4)
    let background = FakeBackgroundScheduler()
    let (scheduler, _) = makeScheduler(outbox: outbox, weighIn: weighIn, gate: gate, background: background, sleep: sleep)
    _ = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.0, date: nil))

    scheduler.startForeground()
    #expect(scheduler.isForegroundLoopRunning)
    #expect(background.cancellations == [OutboxRetryScheduler.refreshTaskIdentifier]) // foreground owns retry now
    scheduler.startForeground() // idempotent
    while sleep.requested.count < 4 { await Task.yield() }
    while scheduler.isForegroundLoopRunning { await Task.yield() }

    #expect(sleep.requested == [.seconds(30), .seconds(60), .seconds(120), .seconds(240)])
    #expect(try outbox.pending()[0].attempts == 4)
}

@Test @MainActor func stopForegroundHandsPendingRowsToABackgroundRefresh() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider(); let gate = GateRespondFakeProvider()
    gate.error = .network("offline")
    let background = FakeBackgroundScheduler()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let (scheduler, _) = makeScheduler(outbox: outbox, weighIn: weighIn, gate: gate, background: background, now: now)
    #expect(scheduler.registerBackgroundTask())
    _ = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .yes))
    _ = await scheduler.foregroundTick() // attempt 1 fails → streak 1

    scheduler.stopForeground()

    #expect(scheduler.isForegroundLoopRunning == false)
    #expect(background.submissions.count == 1)
    #expect(background.submissions[0].0 == OutboxRetryScheduler.refreshTaskIdentifier)
    #expect(background.submissions[0].1 == now.addingTimeInterval(30))
}

@Test @MainActor func stopForegroundBooksNothingWhenTheOutboxIsEmpty() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let background = FakeBackgroundScheduler()
    let (scheduler, _) = makeScheduler(outbox: outbox, weighIn: WeighInFakeProvider(), gate: GateRespondFakeProvider(), background: background)
    scheduler.registerBackgroundTask()
    scheduler.stopForeground()
    #expect(background.submissions.isEmpty)
}

// MARK: - Simulated BG refresh (the test injects the scheduler)

@Test @MainActor func simulatedBackgroundRefreshDrainsBothKindsAndDoesNotRebook() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider(); let gate = GateRespondFakeProvider()
    let background = FakeBackgroundScheduler()
    let (scheduler, _) = makeScheduler(outbox: outbox, weighIn: weighIn, gate: gate, background: background)
    #expect(scheduler.registerBackgroundTask())
    #expect(scheduler.backgroundRegistered)
    #expect(background.registered.keys.contains(OutboxRetryScheduler.refreshTaskIdentifier))
    _ = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.0, date: nil))
    _ = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .override, overrideReason: "Clinician guidance"))

    let ok = await background.fire()

    #expect(ok == true)
    #expect(try outbox.pending().isEmpty)
    #expect(gate.respondCalls.count == 1)
    #expect(background.submissions.isEmpty) // nothing left → no re-book
}

@Test @MainActor func backgroundRefreshRebooksWithBackoffWhileRowsRemainAndReportsFailure() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = WeighInFakeProvider(); let gate = GateRespondFakeProvider()
    weighIn.error = .network("offline")
    let background = FakeBackgroundScheduler()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let (scheduler, _) = makeScheduler(outbox: outbox, weighIn: weighIn, gate: gate, background: background, now: now)
    scheduler.registerBackgroundTask()
    _ = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.0, date: nil))

    let first = await background.fire()
    #expect(first == false) // delivered nothing, rows remain
    #expect(background.submissions.count == 1)
    #expect(background.submissions[0].1 == now.addingTimeInterval(30))

    let second = await background.fire()
    #expect(second == false)
    #expect(background.submissions.count == 2)
    #expect(background.submissions[1].1 == now.addingTimeInterval(60)) // backoff carried across BG launches

    // Cap: after many failed launches the re-book never exceeds 15 min.
    for _ in 0..<10 { _ = await background.fire() }
    #expect(background.submissions.last?.1 == now.addingTimeInterval(15 * 60))
}

@Test @MainActor func registrationIsRefusedWhenTheIdentifierIsNotPermitted() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let background = FakeBackgroundScheduler()
    background.permitted = false
    let (scheduler, _) = makeScheduler(outbox: outbox, weighIn: WeighInFakeProvider(), gate: GateRespondFakeProvider(), background: background)
    #expect(scheduler.registerBackgroundTask() == false)
    #expect(scheduler.backgroundRegistered == false)
    scheduler.scheduleBackgroundRefresh(after: .seconds(30))
    #expect(background.submissions.isEmpty) // unregistered → never submits
}

@Test @MainActor func aMissingDrainerMakesAPassANoOp() async throws {
    let sleep = RecordingSleep()
    let scheduler = OutboxRetryScheduler(drainerSource: { nil }, background: nil, sleep: { try await sleep.sleep($0) })
    let delay = await scheduler.foregroundTick()
    #expect(delay == scheduler.idleInterval)
    #expect(scheduler.consecutiveIncompletePasses == 0)
}

@Test func refreshIdentifierMatchesTheProjectYmlEntry() {
    #expect(OutboxRetryScheduler.refreshTaskIdentifier == "toby913.JournalInsight.outboxRefresh")
}

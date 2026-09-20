import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W9.5-L1 (P-weigh-in + P-hub-watchdog, scout S1-1): `WeighInViewModel.submit`,
// `HubWatchdog.onReachableAgain` and `OutboxRetryScheduler`'s foreground loop can all call the
// drainer while an earlier pass is still awaiting the hub. Before this lane each caller re-read
// `pending()` and POSTed the same row again (double weigh-in / double gate-respond). Now one pass
// is in flight at a time and an overlapping caller awaits — and receives — that pass's result.

/// A `WeighInProviding` whose POST parks until the test releases it, so a second drain call can
/// land mid-await deterministically. Counts calls — that count IS the assertion.
private final class SuspendingWeighInProvider: WeighInProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0

    func logWeighin(weightKg: Double, date: String?) async throws -> WeighinResult {
        lock.withLock { calls += 1 }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock { continuations.append(c) }
        }
        return WeighinResult(status: "ok", weightKg: weightKg, date: date ?? "2026-09-20", garminConfirmed: true)
    }

    /// Lets every parked POST complete.
    func release() {
        let parked = lock.withLock { let c = continuations; continuations = []; return c }
        parked.forEach { $0.resume() }
    }

    /// Spins (cooperatively) until the provider has been entered `n` times.
    func waitForCalls(_ n: Int) async {
        for _ in 0..<2_000 {
            if lock.withLock({ calls }) >= n { return }
            await Task.yield()
        }
    }
}

private final class SuspendingGateProvider: GateRespondProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var respondCalls = 0

    func respondGate(choice: GateChoice, overrideReason: String, windowDays: Int) async throws -> GateRespondResult {
        lock.withLock { respondCalls += 1 }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock { continuations.append(c) }
        }
        return GateRespondResult(pdfRequested: false, logId: 7)
    }

    func logFeel(feelScore: Int, notes: String, date: String?) async throws -> FeelResult { FeelResult(feelId: 1) }

    func release() {
        let parked = lock.withLock { let c = continuations; continuations = []; return c }
        parked.forEach { $0.resume() }
    }

    func waitForCalls(_ n: Int) async {
        for _ in 0..<2_000 {
            if lock.withLock({ respondCalls }) >= n { return }
            await Task.yield()
        }
    }
}

@Test @MainActor func overlappingDrainOnceCallsPostOnePendingRowExactlyOnce() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let provider = SuspendingWeighInProvider()
    let drainer = OutboxDrainer(outbox: outbox, weighIn: provider, gateRespond: nil)
    let id = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 82.5, date: nil))

    // First caller (think `WeighInViewModel.submit`) is parked inside the POST…
    let first = Task { @MainActor in await drainer.drainOnce() }
    await provider.waitForCalls(1)
    #expect(provider.calls == 1)

    // …when a second caller (the retry scheduler's tick) lands on the same pending row.
    let second = Task { @MainActor in await drainer.drainOnce() }
    for _ in 0..<50 { await Task.yield() } // give the second caller every chance to re-read `pending()`
    #expect(provider.calls == 1, "the overlapping caller must not start a second POST")

    provider.release()
    let firstResults = await first.value
    let secondResults = await second.value

    #expect(provider.calls == 1)
    guard case .success(.weighIn(let r1)) = firstResults[id] else { Issue.record("first caller: expected weigh-in success"); return }
    guard case .success(.weighIn(let r2)) = secondResults[id] else { Issue.record("overlapping caller must receive the in-flight result"); return }
    #expect(r1 == r2)
    #expect(try outbox.pending().isEmpty) // one markSent — the row is gone, and nothing tried to re-send it
}

@Test @MainActor func drainOnForegroundLandingMidAwaitNeverPostsTheRowTwice() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let gate = SuspendingGateProvider()
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: gate)
    let id = try outbox.enqueue(kind: OutboxDrainer.gateRespondKind, payload: GateRespondBody(choice: .yes))

    let inTap = Task { @MainActor in await drainer.drainOnce() }
    await gate.waitForCalls(1)

    // The hub comes back reachable while the in-tap POST is still awaiting: the watchdog fires.
    let watchdog = Task { @MainActor in await drainer.drainOnForeground() }
    for _ in 0..<50 { await Task.yield() }
    #expect(gate.respondCalls == 1, "`drainOnForeground` mid-await must join, not re-POST")

    gate.release()
    let tapResults = await inTap.value
    let watchdogResults = await watchdog.value

    #expect(gate.respondCalls == 1)
    guard case .success(.gateRespond) = tapResults[id] else { Issue.record("in-tap caller: expected success"); return }
    guard case .success(.gateRespond) = watchdogResults[id] else { Issue.record("watchdog must receive the in-flight result"); return }
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func aDrainAfterThePreviousOneFinishedReadsPendingAgain() async throws {
    // The guard is per-pass, not sticky: once a pass has returned, the next call re-reads `pending()`
    // and drains whatever was enqueued in the meantime.
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let provider = SuspendingWeighInProvider()
    let drainer = OutboxDrainer(outbox: outbox, weighIn: provider, gateRespond: nil)
    let a = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 82.0, date: nil))

    let first = Task { @MainActor in await drainer.drainOnce() }
    await provider.waitForCalls(1)
    provider.release()
    let firstResults = await first.value
    #expect(firstResults[a] != nil)

    let b = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 81.5, date: nil))
    let second = Task { @MainActor in await drainer.drainOnce() }
    await provider.waitForCalls(2)
    provider.release()
    let secondResults = await second.value

    #expect(provider.calls == 2)
    #expect(secondResults[b] != nil)
    #expect(secondResults[a] == nil)
    #expect(try outbox.pending().isEmpty)
}

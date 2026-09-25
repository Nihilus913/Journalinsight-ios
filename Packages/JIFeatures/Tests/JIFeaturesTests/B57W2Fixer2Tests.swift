import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-B57-W2 fixer round 2: verifier failures RF3-STATUS and BUG-38/RF2-BURN.

// MARK: - RF3-STATUS: the Goals save status reflects delivery, not a lost drain race

/// A weigh-in POST that parks until released, so a drain pass is in flight when the mirror pushes.
private final class ParkedWeighIn: WeighInProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var calls = 0

    func logWeighin(weightKg: Double, date: String?) async throws -> WeighinResult {
        lock.withLock { calls += 1 }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in lock.withLock { parked.append(c) } }
        return WeighinResult(status: "ok", weightKg: weightKg, date: date ?? "2026-09-25", garminConfirmed: true)
    }

    func release() { lock.withLock { let p = parked; parked = []; return p }.forEach { $0.resume() } }

    func waitForCall() async {
        for _ in 0..<2_000 { if lock.withLock({ calls }) >= 1 { return }; await Task.yield() }
    }
}

private func macros(_ kcal: Double, protein: Double? = nil) -> MacroGoals {
    MacroGoals(kcal: KcalGoal(goalKcal: kcal, basis: .includesDeficit), proteinG: protein)
}

/// A retry-scheduler pass that started BEFORE the save enqueued its row is still in flight when
/// the mirror drains: the mirror used to get that pass's results (without its row) and report
/// "hub sync pending" although the hub was up. It must run its own pass and report delivery.
@Test @MainActor func fixer2_pushThatRacesAnInFlightPassStillDelivers() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let weighIn = ParkedWeighIn()
    let hub = GoalsRecorder()
    let drainer = OutboxDrainer(outbox: outbox, weighIn: weighIn, gateRespond: nil, goals: hub)
    _ = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 82, date: nil))
    let earlier = Task { @MainActor in await drainer.drainOnce() }
    await weighIn.waitForCall()

    let push = Task { @MainActor in await GoalsMirror(outbox: outbox, drainer: drainer).push(macros(1800, protein: 150)) }
    for _ in 0..<50 { await Task.yield() }
    weighIn.release()
    _ = await earlier.value
    let outcome = await push.value

    guard case .delivered(let server) = outcome else { Issue.record("expected delivered, got \(outcome)"); return }
    #expect(server?.nutrition.proteinG == 150)
    #expect(hub.patches.count == 1)
    #expect(try outbox.pending().isEmpty)
}

/// Another drainer instance (the app's retry scheduler) delivered the row first: the outbox is
/// empty and the hub has it, so the mirror reports delivered — never "pending".
@Test @MainActor func fixer2_rowDeliveredByAnotherDrainerCountsAsDelivered() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = GoalsRecorder()
    let other = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, goals: hub)
    // The mirror's own drainer cannot deliver goals rows at all; only `other` can.
    let mirrorDrainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, goals: DeliverViaOther(other: other))
    let outcome = await GoalsMirror(outbox: outbox, drainer: mirrorDrainer).push(macros(1800))
    guard case .delivered = outcome else { Issue.record("expected delivered, got \(outcome)"); return }
    #expect(try outbox.pending().isEmpty)
    #expect(hub.patches.count == 1)
}

/// Stands in for the race where a second drainer instance retires the row while this pass runs:
/// its PUT runs the OTHER drainer's pass (which marks the row sent), then fails this attempt as a
/// duplicate would — leaving this pass with no success for the row.
private final class DeliverViaOther: GoalsProviding, @unchecked Sendable {
    let other: OutboxDrainer
    init(other: OutboxDrainer) { self.other = other }
    func updateGoals(_ patch: GoalsUpdate) async throws -> Goals {
        _ = await other.drainOnce()
        throw HubError.network("raced")
    }
}

@Test @MainActor func fixer2_offlinePushStillReportsQueued() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = GoalsRecorder(); hub.fail = .network("down")
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, goals: hub)
    #expect(await GoalsMirror(outbox: outbox, drainer: drainer).push(macros(1800)) == .queued)
    #expect(try outbox.pending().count == 1)
    #expect(await GoalsMirror(outbox: outbox, drainer: drainer).push(.unset) == .nothingToSend)
}

/// The hub GET failed at load (phase .error → "Hub offline…"), then the save's PUT landed: the
/// footer must say saved, not "Hub offline" / "hub sync pending".
private nonisolated struct LoadFailsProvider: GoalsSetupProviding {
    let inner = MockDataProvider()
    func energy(windowDays: Int) async throws -> EnergyReport { try await inner.energy(windowDays: windowDays) }
    func goals() async throws -> Goals { throw HubError.network("timed out") }
    func updateGoals(_ patch: GoalsUpdate) async throws -> Goals { try await inner.updateGoals(patch) }
}

@Test @MainActor func fixer2_deliveredSaveClearsTheHubOfflineAndPendingStatus() async throws {
    let db = try AppDatabase.inMemory()
    let outbox = Outbox(db: db)
    let hub = GoalsRecorder()
    let mirror = GoalsMirror(outbox: outbox, drainer: OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, goals: hub))
    let vm = GoalsSetupViewModel(provider: LoadFailsProvider(), macroStore: MacroGoalsStore(prefs: PrefStore(db: db)), mirror: mirror)
    await vm.load()
    guard case .error = vm.phase else { Issue.record("load should fail"); return }
    #expect(await vm.saveNutrition(macros(1800, protein: 150)) == .saved)
    #expect(vm.hubPending == false)
    #expect(vm.phase == .loaded)
    #expect(vm.goals?.nutrition.proteinG == 150)
}

// MARK: - BUG-38 / RF2-BURN: one burn number, from the source the card's copy names

private let hubDays = [EnergyDay(date: "2026-09-22", tdeeRaw: 2600, tdeeCorrected: 2750),
                       EnergyDay(date: "2026-09-23", tdeeRaw: 2616, tdeeCorrected: 2746)]

/// Health empty: the card says Apple Health, so it shows "— Not in Health yet", never the hub's
/// tdee_raw average under Apple Health copy.
@Test func fixer2_burnCardWithEmptyHealthShowsNotInHealthYetNotTheHubAverage() {
    let v = energyBurnCardValue(window: nil, reason: "Not in Health yet")
    #expect(v.kcal == nil)
    #expect(v.caption == "Not in Health yet")
    #expect(energyBurnAverage(days: hubDays, today: "2026-09-25") != nil)   // the hub has a number; it is not used
}

@Test func fixer2_burnCardWithHealthShowsTheHealthBurn() {
    let window = EnergyBurnWindow(completeDays: 7, settled: true, burnKcal: 2410, basalKcal: 1900, activeKcal: 510)
    let v = energyBurnCardValue(window: window, reason: nil)
    #expect(v.kcal == 2410)
    #expect(v.caption == "kcal a day")
}

@Test func fixer2_burnCardCalibratingShowsTheReason() {
    let window = EnergyBurnWindow(completeDays: 1, settled: false, burnKcal: nil, basalKcal: nil, activeKcal: nil)
    let v = energyBurnCardValue(window: window, reason: "Calibrating")
    #expect(v.kcal == nil)
    #expect(v.caption == "Calibrating")
}

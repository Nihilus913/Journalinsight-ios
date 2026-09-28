import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-B57-W2 fixer round 2: verifier failures RF3-STATUS and BUG-38/RF2-BURN.

// MARK: - RF3-STATUS: the Goals save status reflects delivery, not a lost drain race
// W-TGT L3: the goals copy is the targets document (`TargetsMirror`, outbox kind `targets`); the
// drain-race logic moved with it (L1 `TargetsMirrorTests`). What stays here is the save status.

private func macros(_ kcal: Double, protein: Double? = nil) -> MacroGoals {
    MacroGoals(kcal: KcalGoal(goalKcal: kcal, basis: .includesDeficit), proteinG: protein)
}

@MainActor private func targetsGoalsMirror(_ db: AppDatabase, hub: TargetsHubFake) throws -> (GoalsMirror, Outbox) {
    let outbox = Outbox(db: db)
    try TargetsStore(prefs: PrefStore(db: db)).save(.empty)   // after the §5 import
    return (GoalsMirror(prefs: PrefStore(db: db), outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: hub)), outbox)
}

@Test @MainActor func fixer2_offlinePushStillReportsQueued() async throws {
    let db = try AppDatabase.inMemory()
    let hub = TargetsHubFake(); hub.fail = .network("down")
    let (mirror, outbox) = try targetsGoalsMirror(db, hub: hub)
    #expect(await mirror.push(macros(1800)) == .queued)
    #expect(try outbox.pending().map(\.kind) == [TargetsDocument.outboxKind])
}

/// Before the §5 import there is no document to send: the import carries the goals over.
@Test @MainActor func fixer2_noDocumentYetSendsNothing() async throws {
    let db = try AppDatabase.inMemory()
    let outbox = Outbox(db: db)
    let mirror = GoalsMirror(prefs: PrefStore(db: db), outbox: outbox, drainer: OutboxDrainer(outbox: outbox, hub: TargetsHubFake()))
    #expect(await mirror.push(macros(1800)) == .nothingToSend)
    #expect(try outbox.pending().isEmpty)
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
    let hub = TargetsHubFake()
    let (mirror, _) = try targetsGoalsMirror(db, hub: hub)
    let vm = GoalsSetupViewModel(provider: LoadFailsProvider(), macroStore: MacroGoalsStore(prefs: PrefStore(db: db)), mirror: mirror)
    await vm.load()
    guard case .error = vm.phase else { Issue.record("load should fail"); return }
    #expect(await vm.saveNutrition(macros(1800, protein: 150)) == .saved)
    #expect(vm.hubPending == false)
    #expect(vm.phase == .loaded)
    #expect(hub.puts.last?.goals.proteinG == 150)
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

import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

/// W-TGT L3: the goals copy is the ONE targets document (`PUT /planning/targets`), after the §5
/// import (the document exists).
@MainActor private func fixture(hubFails: HubError? = nil) throws -> (GoalsMirror, Outbox, MacroGoalsStore, TargetsHubFake) {
    let db = try AppDatabase.inMemory()
    let outbox = Outbox(db: db)
    let prefs = PrefStore(db: db)
    try TargetsStore(prefs: prefs).save(.empty)
    let store = MacroGoalsStore(prefs: prefs)
    let hub = TargetsHubFake(); hub.fail = hubFails
    let drainer = OutboxDrainer(outbox: outbox, hub: hub)
    return (GoalsMirror(prefs: prefs, outbox: outbox, drainer: drainer), outbox, store, hub)
}

@MainActor private final class SaveCounter { var n = 0 }

/// Burn 2300 from 3 complete days (test data).
private let burn2300 = EnergyBand.burnWindow(
    days: (21...23).map { EnergyBandDay(date: "2026-09-\($0)", basalKcal: 1800, activeKcal: 500, intakeKcal: 1800) },
    today: "2026-09-24")

private func goals(_ goal: Double, _ basis: KcalGoalBasis, protein: Double? = nil) -> MacroGoals {
    MacroGoals(kcal: KcalGoal(goalKcal: goal, basis: basis), proteinG: protein)
}

/// Round trip, phone half: user save → Outbox row (kind `targets`) → the ONE document the hub
/// receives, with the user's goals and nothing invented.
@Test @MainActor func pushSendsTheTargetsDocumentWithTheUsersGoals() async throws {
    let (mirror, outbox, _, hub) = try fixture()
    guard case .delivered = await mirror.push(goals(1600, .includesDeficit, protein: 160)) else { Issue.record("not delivered"); return }
    #expect(hub.puts.count == 1)
    #expect(hub.puts.last?.macroGoals == goals(1600, .includesDeficit, protein: 160))
    #expect(hub.puts.last?.goals.sleepH == nil)          // never seeded (D2)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func pushSendsTheTargetNotTheTypedGoal() async throws {
    let (mirror, _, _, hub) = try fixture()
    _ = await mirror.push(goals(2300, .subtractDeficit(.deficit(kcalPerDay: 500))))
    #expect(hub.puts.first?.goal(.kcal) == 1800)
}

@Test @MainActor func unsetGoalsPatchIsNil() {
    #expect(GoalsMirror.patch(for: .unset) == nil)
}

/// Review Focus 3.
@Test @MainActor func offlinePushKeepsTheRowQueued() async throws {
    let (mirror, outbox, _, _) = try fixture(hubFails: .network("down"))
    #expect(await mirror.push(goals(1600, .includesDeficit)) == .queued)
    #expect(try outbox.pending().count == 1)
}

@Test @MainActor func loadWithNothingStoredIsUnsetAndNeverPushes() async throws {
    let (mirror, outbox, store, hub) = try fixture()
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), macroStore: store, mirror: mirror, burnSource: { burn2300 })
    await vm.load()
    #expect(vm.macroGoals == .unset)
    #expect(vm.burnWindow?.burnKcal == 2300)
    #expect(hub.puts.isEmpty)                     // Review Focus 4: only a user save pushes
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func saveNutritionPersistsLocallyAndReportsHubPendingWhenOffline() async throws {
    let (mirror, _, store, _) = try fixture(hubFails: .network("down"))
    let saved = SaveCounter()
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), macroStore: store, mirror: mirror,
                                 burnSource: { burn2300 }, onNutritionSaved: { saved.n += 1 })
    await vm.load()
    let edited = goals(2300, .subtractDeficit(.weeklyLoss(kgPerWeek: 0.5)), protein: 160)   // target 1750
    #expect(vm.bandPreview(for: edited).map { [$0.low, $0.high] } == [1650, 1850])
    #expect(vm.impliedDeficitText(for: edited) == "≈ 550 kcal under what you burn")
    #expect(await vm.saveNutrition(edited) == .saved)
    #expect(try store.load() == edited)
    #expect(vm.hubPending)
    #expect(saved.n == 1)
}

/// The "includes" basis is never subtracted again: goal 1600 → band 1500–1700.
@Test @MainActor func includesDeficitPreviewIsTheGoalPlusMinus100() async throws {
    let (mirror, _, store, _) = try fixture()
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), macroStore: store, mirror: mirror, burnSource: { burn2300 })
    await vm.load()
    #expect(vm.bandPreview(for: goals(1600, .includesDeficit)).map { [$0.low, $0.high] } == [1500, 1700])
    #expect(vm.needsDeficitCheck(goals(1600, .includesDeficit)) == false)   // the prompt is for "subtract" only
}

/// Sanity prompt: goal 1600 − 500 = 1100 against burn 2300 asks first and writes nothing.
@Test @MainActor func saveAsksWhenTheGoalLooksLikeItAlreadyIncludesADeficit() async throws {
    let (mirror, outbox, store, _) = try fixture()
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), macroStore: store, mirror: mirror, burnSource: { burn2300 })
    await vm.load()
    let typed = goals(1600, .subtractDeficit(.deficit(kcalPerDay: 500)))
    #expect(vm.needsDeficitCheck(typed))
    #expect(await vm.saveNutrition(typed) == .needsDeficitCheck)
    #expect(try store.load() == .unset)
    #expect(try outbox.pending().isEmpty)
    // "Yes" in the dialog: the view switches the basis and saves confirmed.
    var yes = typed; yes.kcal?.basis = .includesDeficit
    #expect(await vm.saveNutrition(yes, confirmed: true) == .saved)
    #expect(try store.load().targetKcal == 1600)
}

@Test @MainActor func noBurnNoPrompt() async throws {
    let (mirror, _, store, _) = try fixture()
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), macroStore: store, mirror: mirror, burnSource: { nil })
    await vm.load()
    let typed = goals(1600, .subtractDeficit(.deficit(kcalPerDay: 500)))
    #expect(vm.bandPreview(for: typed).map { [$0.low, $0.high] } == [1000, 1200])   // band needs no Health
    #expect(vm.impliedDeficitText(for: typed) == nil)
    #expect(await vm.saveNutrition(typed) == .saved)
}

@Test func draftStartsWithNoNumbersAndNoChoice() {
    let d = NutritionDraft(.unset)
    #expect(d.goalKcal == nil && d.includesDeficit == nil && d.deficitMode == nil)
    #expect(d.proteinG == nil && d.carbsG == nil && d.fatG == nil)
    #expect(d.canSave)                 // nothing typed: nothing to validate
    #expect(d.goals == .unset)
}

@Test func draftNeedsTheBasisChoiceBeforeItCanSave() {
    var d = NutritionDraft(.unset)
    d.goalKcal = 1600
    #expect(!d.canSave)                // required choice not made
    #expect(d.goals == nil)
    d.includesDeficit = true
    #expect(d.canSave)
    #expect(d.goals?.kcal == KcalGoal(goalKcal: 1600, basis: .includesDeficit))
    d.includesDeficit = false          // "I want JI to subtract a deficit" → the deficit field is required
    #expect(!d.canSave)
    d.deficitMode = .deficit(kcalPerDay: 500)
    #expect(d.goals?.targetKcal == 1100)
    d.deficitMode = .deficit(kcalPerDay: 2000)   // target ≤ 0 is not a plan
    #expect(!d.canSave)
}

@Test func draftRoundTripsStoredGoalsAndTheWeekToggleConverts() {
    let stored = MacroGoals(kcal: KcalGoal(goalKcal: 2300, basis: .subtractDeficit(.deficit(kcalPerDay: 550))), proteinG: 160)
    var d = NutritionDraft(stored)
    #expect(d.goals == stored)
    d.byWeek = true
    #expect(d.deficitMode == .weeklyLoss(kgPerWeek: 0.5))      // 550 · 7 / 7700
    d.byWeek = false
    #expect(d.deficitMode == .deficit(kcalPerDay: 550))
}

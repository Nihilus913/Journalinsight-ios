import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W-FIX5 L2: DEV-15, DEV-16, W4-1, W4-2, W4-3, W4-4 (docs/audits/2026-09-25-regression-bugs.md).

@MainActor private func goalsFixture() throws -> (GoalsSetupViewModel, Outbox, GoalsRecorder) {
    let db = try AppDatabase.inMemory()
    let outbox = Outbox(db: db)
    let hub = GoalsRecorder(); hub.fail = .network("down")
    let mirror = GoalsMirror(outbox: outbox, drainer: OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, goals: hub))
    let vm = GoalsSetupViewModel(provider: GoalsFakeProvider(), macroStore: MacroGoalsStore(prefs: PrefStore(db: db)),
                                 mirror: mirror, hubPendingSource: { GoalsSetupViewModel.goalsPending(in: outbox) })
    return (vm, outbox, hub)
}

// DEV-15: "hub sync pending" clears once the outbox delivered the PUT (another drainer), on the
// next load of the retained model — not only after the next nutrition save.
@Test @MainActor func dev15PendingClearsAfterTheOutboxDelivered() async throws {
    let (vm, outbox, _) = try goalsFixture()
    await vm.load()
    #expect(await vm.saveNutrition(MacroGoals(kcal: KcalGoal(goalKcal: 1800, basis: .includesDeficit))) == .saved)
    #expect(vm.hubPending)
    for row in try outbox.pending() { try outbox.markSent(id: row.id) }   // the retry scheduler delivered it
    await vm.load()
    #expect(!vm.hubPending)
}

// DEV-15: a row still queued from an earlier session reads as pending on load (the truth).
@Test @MainActor func dev15QueuedRowFromEarlierSessionReadsPending() async throws {
    let (vm, outbox, _) = try goalsFixture()
    _ = try outbox.enqueue(kind: OutboxDrainer.goalsKind, payload: GoalsUpdate(nutrition: .init(kcalGoal: 1800, proteinG: nil, carbsG: nil, fatG: nil)))
    await vm.load()
    #expect(vm.hubPending)
    #expect(!GoalsSetupViewModel.goalsPending(in: Outbox(db: try AppDatabase.inMemory())))
}

// DEV-16: the steps stepper label never groups digits ("15'000" in de_CH).
@Test func dev16StepsLabelHasNoDigitSeparator() {
    #expect(goalsSetupStepsLabel(15000) == "Daily steps: 15000")
    #expect(goalsSetupStepsLabel(500) == "Daily steps: 500")
}

// W4-1: the app's foreground push clears "Not on the hub yet" on a GateConfig that stays open.
@Test @MainActor func w41ForegroundClearsNotOnTheHubYet() async throws {
    let prefs = try PrefStore(db: AppDatabase.inMemory())
    let hub = GateSettingsHubFake(); hub.fail = true
    let name = Notification.Name("fix5.l2.test.active")
    let vm = GateConfigViewModel(targetsProvider: nil, prefStore: prefs, mirror: GateSettingsMirror(prefs: prefs, provider: hub),
                                 foregroundNotification: name, today: { "2026-09-27" })
    vm.loadLocal()
    #expect(await vm.changeHrCap("170"))
    #expect(vm.hubPending)
    hub.fail = false
    NotificationCenter.default.post(name: name, object: nil)
    for _ in 0..<100 where vm.hubPending { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!vm.hubPending)
    #expect(hub.puts.last?.hrCapBpm == 170)
}

@Test @MainActor func w41ForegroundSyncReReadsTheFlag() async throws {
    let prefs = try PrefStore(db: AppDatabase.inMemory())
    let hub = GateSettingsHubFake(); hub.fail = true
    let vm = GateConfigViewModel(targetsProvider: nil, prefStore: prefs, mirror: GateSettingsMirror(prefs: prefs, provider: hub))
    vm.loadLocal()
    await vm.setPreset(.careful)
    #expect(vm.hubPending)
    hub.fail = false
    await vm.foregroundSync()
    #expect(!vm.hubPending)
}

// W4-2: onboarding "Nights so far" = the recovery score's real night count, never a guess.
@Test @MainActor func w42NightsSoFarComesFromTheRecoveryResult() throws {
    let r = RecoveryScoreResult(status: .calibrating, score: nil, raw: nil, components: [], nights: 9)
    #expect(OnboardingViewModel.NightsProgress(recovery: r) == .init(have: 9, need: 14))
    #expect(OnboardingViewModel.NightsProgress(recovery: nil) == nil)
    let prefs = try PrefStore(db: AppDatabase.inMemory())
    let vm = GateConfigViewModel(targetsProvider: nil, prefStore: prefs)
    #expect(vm.makeOnboardingModel(recovery: r).nightsSoFar == .init(have: 9, need: 14))
    #expect(vm.makeOnboardingModel().nightsSoFar == nil)
    #expect(OnboardingCopy.nightsValue(.init(have: 9, need: 14)) == "9")
}

// W4-3: the Settings Reminders count includes the HR-cap re-check.
@Test func w43RemindersTrailingCountsTheHrCapCheck() {
    var prefs = RemindersPrefs()
    #expect(settingsRemindersTrailing(nil, hrCapCheckOn: true) == "1 on")
    #expect(settingsRemindersTrailing(prefs, hrCapCheckOn: false) == "Off")
    prefs.daily["journal"] = .init(enabled: true, time: ReminderTime(hour: 21, minute: 0))
    #expect(settingsRemindersTrailing(prefs, hrCapCheckOn: true) == "2 on")
}

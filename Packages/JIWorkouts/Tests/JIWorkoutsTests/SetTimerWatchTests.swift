import Foundation
import Testing
import JICompute
@testable import JIWorkouts

/// W-B38-B B-5 (gap #28) — rest timer auto-starts after a logged set (haptic once at 0,
/// skip / +15 s) and the timed-set countdown for `kind = timed` logs `duration_s`.
@MainActor
struct SetTimerWatchTests {
    @Test func restAutoStartsAfterALoggedSet() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        await h.vm.logSet()
        #expect(h.vm.timer.phase == .resting)
        #expect(h.vm.remainingSeconds == 120)
    }

    @Test func restUsesNinetySecondsWhenThePlanHasNone() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.row)
        await h.vm.logSet()
        #expect(h.vm.remainingSeconds == StrengthLogViewModel.defaultRestS)
    }

    @Test func hapticFiresOnceAtZero() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        await h.vm.logSet()
        h.now += 60; await h.vm.tick()
        #expect(h.haptics.isEmpty)
        h.now += 60; await h.vm.tick()
        h.now += 1; await h.vm.tick()
        h.now += 1; await h.vm.tick()
        #expect(h.haptics == [.restDone])
        #expect(h.vm.timer.phase == .idle)
    }

    @Test func skipAndAddFifteen() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        await h.vm.logSet()
        h.vm.addRest()
        #expect(h.vm.remainingSeconds == 135)
        h.vm.skipRest()
        #expect(h.vm.timer.phase == .idle)
        h.now += 200; await h.vm.tick()
        #expect(h.haptics.isEmpty) // skipped rest never buzzes
    }

    @Test func editingASetDoesNotRestartRest() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        await h.vm.logSet()
        h.vm.skipRest()
        h.vm.beginEdit(h.vm.sets(for: StrengthLogHarness.bench)[0])
        await h.vm.logSet()
        #expect(h.vm.timer.phase == .idle)
    }

    @Test func timedSetCountsDownThenLogsDuration() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.plank)
        #expect(h.vm.entryDurationS == 45)
        await h.vm.primaryAction() // Double Tap on a timed exercise starts the countdown
        #expect(h.vm.timer.phase == .timedSet)
        #expect(h.vm.sets(for: StrengthLogHarness.plank).isEmpty)
        h.now += 45; await h.vm.tick()
        let sets = h.vm.sets(for: StrengthLogHarness.plank)
        #expect(sets.count == 1)
        #expect(sets.first?.kind == .timed)
        #expect(sets.first?.durationS == 45)
        #expect(sets.first?.reps == nil)
        #expect(sets.first?.weightKg == nil)
        #expect(h.haptics == [.timedDone])
        #expect(h.vm.timer.phase == .resting) // rest follows the timed set
        #expect(h.vm.remainingSeconds == 60)
    }

    @Test func timedSetStoppedEarlyLogsTheElapsedSeconds() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.plank)
        await h.vm.primaryAction()
        h.now += 30
        await h.vm.primaryAction() // second Double Tap stops the plank early
        #expect(h.vm.sets(for: StrengthLogHarness.plank).first?.durationS == 30)
        #expect(h.haptics.isEmpty)
    }
}

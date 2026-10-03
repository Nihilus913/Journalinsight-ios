import Foundation
import Testing
import JICompute
@testable import JIWorkouts

/// W-B38-B B-4/B-6 — the Watch set screen's model: exercise list → set entry prefilled from the
/// last-set defaults (gap #29), log / edit / delete (gap #31), HR vs the cap (SessionCap),
/// Double Tap = log set, the Action Button intent starts the controller.
@MainActor
final class StrengthLogHarness {
    var now = Date(timeIntervalSince1970: 1_791_000_000)
    let engine = FakeStrengthWorkoutEngine()
    let transport = FakeStrengthBridgeTransport()
    var haptics: [StrengthLogHaptic] = []
    lazy var vm: StrengthLogViewModel = {
        let bridge = StrengthSessionWatchBridge(transport: transport)
        let vm = StrengthLogViewModel(controller: StrengthWorkoutSessionController(engine: engine), bridge: bridge,
                                      clock: { [unowned self] in self.now }, haptic: { [unowned self] in self.haptics.append($0) })
        return vm
    }()

    static let bench = StrengthWatchExercise(exerciseKey: "barbell_bench_press", exerciseId: 41, name: "Barbell Bench Press", kind: .reps,
                                             targetSets: 3, targetReps: 8, targetDurationS: nil, nextKg: 62.5, stepKg: 2.5, restS: 120,
                                             muscle: "Chest", lastSet: StrengthWatchLastSet(weightKg: 60, reps: 8, durationS: nil))
    static let row = StrengthWatchExercise(exerciseKey: "cable_row", exerciseId: 42, name: "Cable Row", kind: .reps,
                                           targetSets: 3, targetReps: nil, targetDurationS: nil, nextKg: nil, stepKg: nil, restS: nil,
                                           muscle: "Back", lastSet: StrengthWatchLastSet(weightKg: 45, reps: 10, durationS: nil))
    static let plank = StrengthWatchExercise(exerciseKey: "plank", exerciseId: nil, name: "Plank", kind: .timed,
                                             targetSets: 2, targetReps: nil, targetDurationS: 45, nextKg: nil, stepKg: nil, restS: 60,
                                             muscle: "Core", lastSet: nil)

    func loadPlan(limit: Int? = 175) {
        let plan = StrengthWatchPlan(date: "2026-10-05", planSessionId: 7, title: "Upper A", hrLimitBpm: limit,
                                     exercises: [Self.bench, Self.row, Self.plank])
        transport.canSendToRemoteWorkoutSession = true
        try? transport.updateApplicationContext([StrengthBridgeKeys.plan: try! JSONEncoder().encode(plan)])
        vm.bridge.receive(applicationContext: transport.applicationContext)
    }

    func sentEvents() -> [StrengthBridgeEvent] {
        transport.remoteSends.compactMap { try? StrengthBridgeEnvelope.decode($0).event }
    }
}

@MainActor
struct StrengthLogViewModelTests {
    @Test func noPlanShowsNoExercises() {
        let h = StrengthLogHarness()
        #expect(h.vm.exercises.isEmpty)
        #expect(h.vm.selected == nil)
    }

    @Test func selectingPrefillsFromThePlanThenThisSession() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        #expect(h.vm.entryWeightKg == 62.5) // plan nextKg beats last session's 60
        #expect(h.vm.entryReps == 8)
        h.vm.entryWeightKg = 65
        h.vm.entryReps = 6
        await h.vm.logSet()
        h.vm.select(StrengthLogHarness.row)
        #expect(h.vm.entryWeightKg == 45) // no plan kg → last session
        #expect(h.vm.entryReps == 10)
        h.vm.select(StrengthLogHarness.bench)
        #expect(h.vm.entryWeightKg == 65) // this session's last set wins
        #expect(h.vm.entryReps == 6)
    }

    @Test func crownStepsInTheExerciseStep() {
        let h = StrengthLogHarness()
        h.loadPlan()
        h.vm.select(StrengthLogHarness.bench)
        #expect(h.vm.weightStepKg == 2.5)
        h.vm.setCrownWeight(63.7)
        #expect(h.vm.entryWeightKg == 62.5)
        h.vm.setCrownWeight(-4)
        #expect(h.vm.entryWeightKg == 0)
        h.vm.select(StrengthLogHarness.row)
        #expect(h.vm.weightStepKg == 1.25) // unknown step → microplate step
    }

    @Test func logSetSendsOneSetWithIndexAndSession() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        h.vm.entryRpe = 8
        await h.vm.logSet()
        await h.vm.logSet()
        let sets = h.vm.sets(for: StrengthLogHarness.bench)
        #expect(sets.map(\.setIndex) == [1, 2])
        #expect(sets.first?.weightKg == 62.5)
        #expect(sets.first?.reps == 8)
        #expect(sets.first?.rpe == 8)
        #expect(sets.first?.exerciseId == 41)
        let events = h.sentEvents()
        guard case .sessionStarted(let start) = events.first else { Issue.record("no start"); return }
        #expect(start.planSessionId == 7)
        #expect(start.date == "2026-10-05")
        #expect(events.filter { if case .setLogged = $0 { true } else { false } }.count == 2)
        #expect(sets.allSatisfy { $0.sessionClientId == start.sessionClientId })
    }

    @Test func cannotLogWithoutRepsOrSession() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        h.vm.select(StrengthLogHarness.bench)
        await h.vm.logSet() // no session yet
        #expect(h.vm.sets(for: StrengthLogHarness.bench).isEmpty)
        await h.vm.startSession()
        h.vm.entryReps = nil
        #expect(!h.vm.canLog)
        await h.vm.logSet()
        #expect(h.vm.sets(for: StrengthLogHarness.bench).isEmpty)
    }

    @Test func editAndDeleteALoggedSet() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        await h.vm.logSet()
        let logged = h.vm.sets(for: StrengthLogHarness.bench)[0]
        h.vm.beginEdit(logged)
        #expect(h.vm.editingSetId == logged.clientId)
        h.vm.entryWeightKg = 60
        await h.vm.logSet()
        let edited = h.vm.sets(for: StrengthLogHarness.bench)
        #expect(edited.count == 1)
        #expect(edited[0].weightKg == 60)
        #expect(edited[0].clientId == logged.clientId)
        #expect(h.vm.editingSetId == nil)
        await h.vm.delete(edited[0])
        #expect(h.vm.sets(for: StrengthLogHarness.bench).isEmpty)
        let kinds = h.sentEvents().map { e -> String in
            switch e { case .sessionStarted: "start"; case .setLogged: "log"; case .setEdited: "edit"
            case .setDeleted: "delete"; case .heartRate: "hr"; case .sessionEnded: "end" }
        }
        #expect(kinds == ["start", "log", "edit", "delete"])
    }

    @Test func capStateFollowsLiveHeartRate() async {
        let h = StrengthLogHarness()
        h.loadPlan(limit: nil)
        #expect(h.vm.limitBpm == 175) // the 175 cap holds even when the phone sent no limit
        h.loadPlan(limit: 170)
        #expect(h.vm.capState == .unknown)
        await h.vm.startSession()
        h.engine.emitHeartRate(150, at: h.now)
        #expect(h.vm.capState == .under)
        h.engine.emitHeartRate(160, at: h.now)
        #expect(h.vm.capState == .approaching)
        h.engine.emitHeartRate(171, at: h.now)
        #expect(h.vm.capState == .breach)
        await h.vm.lastLiveSend?.value
        #expect(h.sentEvents().contains(.heartRate(bpm: 171, at: h.now)))
    }

    @Test func endSessionSendsTheWorkoutUUID() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        let uuid = UUID()
        h.engine.savedUUID = uuid
        await h.vm.startSession()
        await h.vm.endSession()
        guard case .sessionEnded(let end) = h.sentEvents().last else { Issue.record("no end"); return }
        #expect(end.hkWorkoutUUID == uuid)
        #expect(h.engine.endCount == 1)
    }

    @Test func doubleTapLogsTheSet() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        await h.vm.startSession()
        h.vm.select(StrengthLogHarness.bench)
        await h.vm.primaryAction()
        #expect(h.vm.sets(for: StrengthLogHarness.bench).count == 1)
    }

    @Test func actionButtonIntentStartsTheController() async {
        let h = StrengthLogHarness()
        h.loadPlan()
        StrengthSessionLauncher.shared.model = h.vm
        await StrengthSessionLauncher.shared.startFromIntent()
        #expect(h.engine.startCount == 1)
        #expect(h.vm.controller.state == .running)
        await StrengthSessionLauncher.shared.startFromIntent() // second press: no second session
        #expect(h.engine.startCount == 1)
        StrengthSessionLauncher.shared.model = nil
    }
}

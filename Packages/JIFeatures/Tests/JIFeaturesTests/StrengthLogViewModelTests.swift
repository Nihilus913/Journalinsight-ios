import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B38-A A-10 — the iPhone logger's model: prefilled from the selected training, local-first
/// writes + `strength` outbox, Complete sends the app-computed advance only with the toggle on.
@MainActor @Suite(.serialized) struct StrengthLogViewModelTests {
    let hub = StrengthFakeHub()
    let db: AppDatabase
    let prefs: PrefStore
    let outbox: Outbox
    let store: StrengthSessionLogStore
    var clock = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-22-ish; fixed

    init() throws {
        db = try AppDatabase.inMemory()
        prefs = PrefStore(db: db); outbox = Outbox(db: db); store = StrengthSessionLogStore(db: db)
    }

    let bench = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "8",
                                currentKg: 50, stepKg: 2.5, nextKg: 50)
    let plank = StrengthLogLift(exerciseId: 9, exerciseKey: "Plank", sets: 2, repsTarget: "45s", currentKg: nil, stepKg: nil, nextKg: nil)

    func model(lifts: [StrengthLogLift]? = nil, provider: (any TrainingProviding)? = nil) -> StrengthLogViewModel {
        let t = clock
        return StrengthLogViewModel(lifts: lifts ?? [bench, plank], sessionId: 1, sessionName: "Upper A", store: store,
                                    outbox: outbox, provider: provider ?? hub, prefs: prefs,
                                    today: { "2026-10-03" }, now: { t })
    }

    @Test func prefillsFromTheSelectedTrainingAndMusclePreview() async {
        let m = model()
        #expect(m.cards.map(\.lift.exerciseKey) == ["Barbell Bench Press", "Plank"])
        #expect(m.cards[0].defaults.weightKg == 50 && m.cards[0].defaults.reps == 8)
        #expect(m.cards[0].muscles == ["Chest", "Front delts", "Triceps"])
        #expect(m.cards[1].lift.isTimed && m.cards[1].lift.timedSeconds == 45)
        #expect(m.session == nil)   // nothing created until the first set
    }

    @Test func liftsPickTheSelectedSessionsExercisesWithProgression() {
        let rows = [
            Exercise(exerciseId: 7, sessionName: "Upper A", exerciseName: "Barbell Bench Press", sets: 3, repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, sessionId: 1),
            Exercise(exerciseId: 8, sessionName: "Lower A", exerciseName: "Squat", sets: 3, repsTarget: "5", currentWeightKg: 80, progressionStepKg: 5, sessionId: 2),
        ]
        let prog = [LiftProgression(exerciseId: 7, name: "Barbell Bench Press", sessionName: "Upper A", currentKg: 50, nextKg: 52.5, state: .due(nextKg: 52.5), sets: 3)]
        let lifts = strengthLogLifts(exercises: rows, session: PlannedSession(id: 1, name: "Upper A", weekday: 5), progressions: prog)
        #expect(lifts.map(\.exerciseKey) == ["Barbell Bench Press"])
        #expect(lifts[0].nextKg == 52.5)
    }

    @Test func logEditDeleteWriteLocallyThenReachTheHub() async throws {
        let m = model()
        let a = try #require(m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8, rpe: 7.5))
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        #expect(m.cards[0].sets.count == 2)
        #expect(m.cards[0].defaults.weightKg == 50 && m.cards[0].defaults.reps == 8)   // this session's last set
        m.editSet(a, weightKg: 52.5, reps: 6, rpe: 9)
        #expect(m.cards[0].sets[0].weightKg == 52.5 && m.cards[0].sets[0].rpe == 9)
        m.deleteSet(m.cards[0].sets[1])
        #expect(m.cards[0].sets.count == 1)
        await m.sync()
        #expect(m.pendingCount == 0)
        #expect(hub.sessions.count == 1)
        #expect(hub.setOrder == [a.clientId])
        #expect(hub.sets[a.clientId]?.weightKg == 52.5 && hub.sets[a.clientId]?.rpe == 9)
    }

    @Test func offlineSetsStayOnThePhoneAndDrainWhenOnline() async throws {
        hub.online = false
        let m = model()
        for _ in 1...3 { m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8) }
        await m.sync()
        #expect(m.pendingCount == 4)   // session create + 3 sets
        #expect(m.syncNote?.contains("saved on this phone") == true)
        #expect(try store.sets(sessionClientId: try #require(m.session).clientId).count == 3)
        hub.online = true
        await m.sync()
        #expect(m.pendingCount == 0 && hub.sets.count == 3)
    }

    @Test func aRepsSetWithoutRepsIsNotLogged() {
        let m = model()
        #expect(m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: nil) == nil)
        #expect(m.error == "Enter the reps.")
        #expect(m.session == nil)
        #expect(m.logSet(exerciseKey: "Plank", weightKg: nil, reps: nil, durationS: 45)?.kind == .timed)
    }

    @Test func completeWithToggleOnSendsTheDueAdvance() async throws {
        let m = model()
        for _ in 1...3 { m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8) }
        #expect(m.autoSuggest)
        await m.complete()
        #expect(m.completedAdvance == [StrengthAdvance(exerciseId: 7, currentWeightKg: 52.5)])
        let sent = try #require(hub.completes.last?.1)
        #expect(sent.advance == [StrengthAdvance(exerciseId: 7, currentWeightKg: 52.5)])
        #expect(m.session?.isComplete == true)
    }

    @Test func completeWithToggleOffSendsAnEmptyAdvance() async throws {
        let m = model()
        m.autoSuggest = false
        #expect(progressionAutoSuggest(prefs: prefs) == false)   // the toggle is the shared setting
        for _ in 1...3 { m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8) }
        await m.complete()
        #expect(hub.completes.last?.1.advance == [])
    }

    @Test func aMissedRepHoldsTheTarget() async {
        let m = model()
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 7)
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        #expect(m.advanceList().isEmpty)
    }

    @Test func reopeningResumesTodaysOpenSession() async {
        let first = model()
        first.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        let again = model()
        await again.load()
        #expect(again.session?.clientId == first.session?.clientId)
        #expect(again.cards[0].sets.count == 1)
    }

    @Test func lastTimeComesFromTheHubWhenThePhoneHasNone() async {
        hub.lastSetsAnswer["Barbell Bench Press"] = [StrengthSetOut(clientId: "old", exerciseKey: "Barbell Bench Press", setIndex: 1, reps: 10, weightKg: 47.5, performedAt: "2026-09-29T07:00:00Z")]
        let noPlan = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: nil, currentKg: nil, stepKg: nil, nextKg: nil)
        let m = model(lifts: [noPlan])
        await m.load()
        #expect(m.cards[0].lastTime.first?.weightKg == 47.5)
        #expect(m.cards[0].defaults == .init(weightKg: 47.5, reps: 10, source: .lastSession))
    }

    @Test func platesUseTheEditableInventory() {
        let m = model()
        #expect(m.plates(for: 52.5) == [15, 1.25])
        m.savePlates(PlateInventory(barKg: 20, pairs: [10, 5, 2.5, 1.25]))
        #expect(m.plates(for: 52.5) == [10, 5, 1.25])
        #expect(model().plates.pairs == [10, 5, 2.5, 1.25])   // persisted
        #expect(PlateInventory.parsePairs("10, 5, 1.25") == [10, 5, 1.25])
        #expect(PlateInventory.parsePairs("10, x") == nil)
    }

    @Test func aLoggedSetStartsTheRestTimer() {
        let m = model()
        m.restSeconds = 120
        m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 8)
        #expect(m.timer.phase == .resting)
        #expect(m.timer.remainingSeconds(at: clock) == 120)
    }
}

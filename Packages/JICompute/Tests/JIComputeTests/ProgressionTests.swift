import Testing
@testable import JICompute

struct ProgressionTests {
    let bench = LiftTarget(name: "Bench press", currentKg: 50, stepKg: 2.5, sets: 3, repsTarget: 8)
    func set(_ n: Int, _ reps: Int?, _ kg: Double?, name: String = "Bench press", cat: String? = nil) -> LoggedSet {
        LoggedSet(exerciseName: name, category: cat, setNumber: n, reps: reps, weightKg: kg)
    }

    @Test func allTargetRepsAtCurrentWeightIsDue() {
        let s = Progression.evaluate(target: bench, lastSession: [set(1, 8, 50), set(2, 9, 50), set(3, 8, 50)], autoSuggest: true)
        #expect(s == .due(nextKg: 52.5))
        #expect(Progression.nextWorkingWeight(target: bench, state: s) == 52.5)
    }

    @Test func oneShortSetIsNotYet() {
        let s = Progression.evaluate(target: bench, lastSession: [set(1, 8, 50), set(2, 7, 50), set(3, 8, 50)], autoSuggest: true)
        #expect(s == .notYet)
        #expect(Progression.nextWorkingWeight(target: bench, state: s) == 50)
    }

    @Test func warmUpsAndOtherWeightsAreIgnored() {
        let s = Progression.evaluate(target: bench, lastSession: [set(1, 12, 40), set(2, 8, 50), set(3, 8, 50), set(4, 8, 50)], autoSuggest: true)
        #expect(s == .due(nextKg: 52.5))
        #expect(Progression.evaluate(target: bench, lastSession: [set(1, 8, 50), set(2, 8, 50)], autoSuggest: true) == .notYet)
    }

    @Test func garminStyleNamesMatch() {
        #expect(Progression.matches(set(1, 8, 50, name: "BENCH_PRESS"), liftName: "Bench press"))
        #expect(Progression.matches(set(1, 8, 50, name: "Bench  Press "), liftName: "bench press"))
        #expect(Progression.matches(LoggedSet(exerciseName: nil, category: "BENCH_PRESS", setNumber: 1, reps: 8, weightKg: 50), liftName: "Bench press"))
        #expect(!Progression.matches(set(1, 8, 50, name: "Incline bench press"), liftName: "Bench press"))
    }

    @Test func noSessionNoTargetAndManual() {
        #expect(Progression.evaluate(target: bench, lastSession: [set(1, 8, 50, name: "Row")], autoSuggest: true) == .noSession)
        let noReps = LiftTarget(name: "Bench press", currentKg: 50, stepKg: 2.5, sets: 3, repsTarget: nil)
        #expect(Progression.evaluate(target: noReps, lastSession: [set(1, 8, 50)], autoSuggest: true) == .noTarget)
        let noStep = LiftTarget(name: "Bench press", currentKg: 50, stepKg: 0, sets: 3, repsTarget: 8)
        #expect(Progression.evaluate(target: noStep, lastSession: [set(1, 8, 50)], autoSuggest: true) == .noTarget)
        let manual = Progression.evaluate(target: bench, lastSession: [set(1, 8, 50), set(2, 8, 52.5)], autoSuggest: false)
        #expect(manual == .manual(lastLiftedKg: 52.5))
        #expect(Progression.nextWorkingWeight(target: bench, state: manual) == 52.5)
        #expect(Progression.nextWorkingWeight(target: bench, state: .manual(lastLiftedKg: nil)) == 50)
    }

    @Test func floatingStepsRoundToTheGram() {
        let t = LiftTarget(name: "Bench press", currentKg: 50.1, stepKg: 0.2, sets: 1, repsTarget: 5)
        #expect(Progression.evaluate(target: t, lastSession: [set(1, 5, 50.1)], autoSuggest: true) == .due(nextKg: 50.3))
    }
}

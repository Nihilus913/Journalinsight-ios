import Testing
@testable import JICompute

/// W-FIX9 fixer (verify r1 FIX9V-1): the plan's names ("DB Shoulder Press") against Garmin's
/// (`DUMBBELL_SHOULDER_PRESS`) — the hub's `garmin_workout_codec.EXERCISE_MAP`, mirrored.
struct ExerciseAliasTests {
    func set(_ name: String?, _ cat: String?) -> LoggedSet {
        LoggedSet(exerciseName: name, category: cat, setNumber: 1, reps: 10, weightKg: 12)
    }

    /// The four plan lifts the verifier found never matching `core.exercise_set` (prod names).
    @Test func abbreviatedPlanLiftsMatchTheirGarminNames() {
        #expect(Progression.matches(set("DUMBBELL_SHOULDER_PRESS", "SHOULDER_PRESS"), liftName: "DB Shoulder Press"))
        #expect(Progression.matches(set("DUMBBELL_BICEPS_CURL", "CURL"), liftName: "DB Biceps Curl"))
        #expect(Progression.matches(set("SEATED_DUMBBELL_OVERHEAD_TRICEPS_EXTENSION", "TRICEPS_EXTENSION"),
                                    liftName: "KB Overhead Triceps Extension"))
        #expect(Progression.matches(set("BARBELL_ROLLOUT", "CORE"), liftName: "Ab Roller"))
    }

    /// A category-only set (Garmin logged no exercise name) counts for the plan lift of that category.
    @Test func aNamelessSetMatchesByItsCategory() {
        #expect(Progression.matches(set(nil, "TRICEPS_EXTENSION"), liftName: "KB Overhead Triceps Extension"))
        #expect(Progression.matches(set(nil, "SHOULDER_PRESS"), liftName: "DB Shoulder Press"))
    }

    /// A different named exercise in the same category never counts (a tabletop dip is not the triceps extension).
    @Test func anotherNamedExerciseOfTheSameCategoryDoesNot() {
        #expect(!Progression.matches(set("TABLETOP_DIP", "TRICEPS_EXTENSION"), liftName: "KB Overhead Triceps Extension"))
        #expect(!Progression.matches(set("DEAD_BUG", "HIP_STABILITY"), liftName: "Ab Roller"))
        #expect(!Progression.matches(set("DUMBBELL_BICEPS_CURL", "CURL"), liftName: "DB Shoulder Press"))
        #expect(!Progression.matches(set(nil, "CORE"), liftName: "Plank"))
    }

    @Test func theProgressionRuleSeesTheDbLiftsToo() {
        let target = LiftTarget(name: "DB Shoulder Press", currentKg: 12, stepKg: 2, sets: 3, repsTarget: 10)
        let logged = (1...3).map { LoggedSet(exerciseName: "DUMBBELL_SHOULDER_PRESS", category: "SHOULDER_PRESS",
                                             setNumber: $0, reps: 10, weightKg: 12) }
        #expect(Progression.evaluate(target: target, lastSession: logged, autoSuggest: true) == .due(nextKg: 14))
    }
}

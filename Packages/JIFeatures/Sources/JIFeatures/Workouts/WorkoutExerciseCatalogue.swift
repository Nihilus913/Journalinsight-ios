import Foundation
import JICore

/// One pickable strength exercise: our name (`exercise_key`, the app's exercise identity — spec
/// §10.1) and the Garmin enums the hub validates it against (spec §2.1 / §9).
public nonisolated struct ExerciseOption: Hashable, Sendable, Identifiable {
    public var key: String
    public var garminCategory: String
    public var garminExercise: String?
    public var id: String { key }
    public init(key: String, garminCategory: String, garminExercise: String?) {
        self.key = key; self.garminCategory = garminCategory; self.garminExercise = garminExercise
    }
}

/// W-B40 L2 — the editor's exercise picker (spec §4: "our known exercises", no catalogue browser).
/// Seeded from HT `EXERCISE_MAP` (`scripts/push_garmin_workouts.py`, all live-validated against
/// Garmin's catalogue per the B-40 scout), plus every exercise already used in the library, so an
/// imported exercise is always pickable again.
public nonisolated enum WorkoutExerciseCatalogue {
    public static let known: [ExerciseOption] = [
        ExerciseOption(key: "Barbell Bench Press", garminCategory: "BENCH_PRESS", garminExercise: "BARBELL_BENCH_PRESS"),
        ExerciseOption(key: "Barbell Row", garminCategory: "ROW", garminExercise: "BARBELL_ROW"),
        ExerciseOption(key: "DB Shoulder Press", garminCategory: "SHOULDER_PRESS", garminExercise: "DUMBBELL_SHOULDER_PRESS"),
        ExerciseOption(key: "DB Biceps Curl", garminCategory: "CURL", garminExercise: "DUMBBELL_BICEPS_CURL"),
        ExerciseOption(key: "Diamond Push-Up", garminCategory: "PUSH_UP", garminExercise: "DIAMOND_PUSH_UP"),
        ExerciseOption(key: "Dead Bug", garminCategory: "HIP_STABILITY", garminExercise: "DEAD_BUG"),
        ExerciseOption(key: "Plank", garminCategory: "PLANK", garminExercise: "PLANK"),
        ExerciseOption(key: "KB Overhead Triceps Extension", garminCategory: "TRICEPS_EXTENSION", garminExercise: nil),
        ExerciseOption(key: "Ab Roller", garminCategory: "CORE", garminExercise: "BARBELL_ROLLOUT"),
    ]

    /// `known`, then any exercise the library already uses that is not in it (first use wins).
    public static func options(from templates: [WorkoutTemplate]) -> [ExerciseOption] {
        var seen = Set(known.map(\.key))
        var extra: [ExerciseOption] = []
        for t in templates {
            for seg in t.effectiveSegments {
                for step in seg.steps {
                    guard let s = step.strength, !seen.contains(s.exerciseKey) else { continue }
                    seen.insert(s.exerciseKey)
                    extra.append(ExerciseOption(key: s.exerciseKey, garminCategory: s.garminCategory, garminExercise: s.garminExercise))
                }
            }
        }
        return known + extra.sorted { $0.key < $1.key }
    }
}

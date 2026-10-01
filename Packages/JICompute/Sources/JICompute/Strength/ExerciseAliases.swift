/// W-FIX9 fixer (verify r1 FIX9V-1): the plan's lift names against what Garmin logs. Mirrors the
/// hub's `app/planning/garmin_workout_codec.py` `EXERCISE_MAP` (plan name → Garmin category +
/// exercise name) — HT `tests/test_app_hub_path_contract.py` checks every entry there is here.
/// Extra names are what Garmin logged in `core.exercise_set` for the same lift.
public nonisolated struct ExerciseAlias: Sendable, Equatable {
    /// Garmin's `exercise_category` ("SHOULDER_PRESS").
    public let category: String
    /// Garmin's `exercise_name`s that are this lift ("DUMBBELL_SHOULDER_PRESS").
    public let garminNames: [String]
}

public nonisolated enum ExerciseAliases {
    /// Keyed by the plan name as written in `plan.session_exercises` / `EXERCISE_MAP`.
    public static let byPlanName: [String: ExerciseAlias] = [
        "Barbell Bench Press": ExerciseAlias(category: "BENCH_PRESS", garminNames: ["BARBELL_BENCH_PRESS"]),
        "Barbell Row": ExerciseAlias(category: "ROW", garminNames: ["BARBELL_ROW"]),
        "DB Shoulder Press": ExerciseAlias(category: "SHOULDER_PRESS", garminNames: ["DUMBBELL_SHOULDER_PRESS"]),
        "DB Biceps Curl": ExerciseAlias(category: "CURL", garminNames: ["DUMBBELL_BICEPS_CURL"]),
        "Diamond Push-Up": ExerciseAlias(category: "PUSH_UP", garminNames: ["DIAMOND_PUSH_UP"]),
        "Dead Bug": ExerciseAlias(category: "HIP_STABILITY", garminNames: ["DEAD_BUG"]),
        "Plank": ExerciseAlias(category: "PLANK", garminNames: ["PLANK"]),
        // The codec sends this one category-only; the Watch logs it seated with dumbbells.
        "KB Overhead Triceps Extension": ExerciseAlias(category: "TRICEPS_EXTENSION",
                                                       garminNames: ["SEATED_DUMBBELL_OVERHEAD_TRICEPS_EXTENSION"]),
        "Ab Roller": ExerciseAlias(category: "CORE", garminNames: ["BARBELL_ROLLOUT"]),
        "Jump Rope": ExerciseAlias(category: "CARDIO", garminNames: ["JUMP_ROPE"]),
    ]

    private static let normalized: [String: ExerciseAlias] = Dictionary(
        byPlanName.map { (Progression.normalizedName($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })

    public static func alias(forPlanName name: String) -> ExerciseAlias? {
        normalized[Progression.normalizedName(name)]
    }

    /// Whether a logged set is the plan lift `liftName` by the alias: one of its Garmin names, or —
    /// only when Garmin logged no name at all — its category. A different named exercise of the
    /// same category (a tabletop dip under TRICEPS_EXTENSION) never counts.
    public static func matches(exerciseName: String?, category: String?, liftName: String) -> Bool {
        guard let alias = alias(forPlanName: liftName) else { return false }
        let name = exerciseName.map(Progression.normalizedName) ?? ""
        if !name.isEmpty { return alias.garminNames.contains { Progression.normalizedName($0) == name } }
        return category.map(Progression.normalizedName) == Progression.normalizedName(alias.category)
    }
}

/// B-90 p1 — the ONE exercise → {muscle: weight} table (primary 1.0, secondary 0.5) and the ONE
/// muscle vocabulary. Replaces the app's ad-hoc `StrengthMuscles.targets` (logger preview) and
/// `ExerciseLibrary.categoryMuscles` (library rows). Python twin: HT `app/training/muscle_map.py`;
/// both must equal HT `tests/fixtures/muscle_map.json` (byte copy in Tests/…/Resources/golden).
/// Keyed on the plan `exerciseKey`; a Garmin set resolves through `ExerciseAliases`' Garmin names,
/// else its category. Unmapped → nil, never a guess. Order matters: the first muscle is primary.
public nonisolated enum Muscle: String, Sendable, CaseIterable, Hashable {
    case chest, frontDelts = "front_delts", shoulders, triceps, upperBack = "upper_back", lats, traps
    case biceps, forearms, core, abs, deepCore = "deep_core", hipFlexors = "hip_flexors"
    case lowerBack = "lower_back", glutes, quads, hamstrings, calves

    public var displayName: String {
        switch self {
        case .chest: "Chest"
        case .frontDelts: "Front delts"
        case .shoulders: "Shoulders"
        case .triceps: "Triceps"
        case .upperBack: "Upper back"
        case .lats: "Lats"
        case .traps: "Traps"
        case .biceps: "Biceps"
        case .forearms: "Forearms"
        case .core: "Core"
        case .abs: "Abs"
        case .deepCore: "Deep core"
        case .hipFlexors: "Hip flexors"
        case .lowerBack: "Lower back"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        }
    }
}

public nonisolated struct MuscleWeight: Sendable, Equatable, Hashable {
    public let muscle: Muscle
    public let weight: Double
    public init(_ muscle: Muscle, _ weight: Double) { self.muscle = muscle; self.weight = weight }
}

public nonisolated enum MuscleMap {
    public static let primary = 1.0
    public static let secondary = 0.5

    private static func p(_ m: Muscle) -> MuscleWeight { MuscleWeight(m, primary) }
    private static func s(_ m: Muscle) -> MuscleWeight { MuscleWeight(m, secondary) }

    /// Catalogue lifts (`WorkoutExerciseCatalogue.known`), keyed by plan name.
    public static let exercises: [String: [MuscleWeight]] = [
        "Barbell Bench Press": [p(.chest), s(.frontDelts), s(.triceps)],
        "Barbell Row": [p(.upperBack), s(.lats), s(.biceps)],
        "DB Shoulder Press": [p(.shoulders), s(.triceps)],
        "DB Biceps Curl": [p(.biceps), s(.forearms)],
        "Diamond Push-Up": [p(.triceps), s(.chest)],
        "Dead Bug": [p(.deepCore), s(.hipFlexors)],
        "Plank": [p(.core), s(.shoulders)],
        "KB Overhead Triceps Extension": [p(.triceps)],
        "Ab Roller": [p(.abs), s(.lats)],
    ]

    /// Shorter names the logger has always accepted (normalized form) → plan name.
    public static let exerciseAliases: [String: String] = [
        "bench press": "Barbell Bench Press", "bench": "Barbell Bench Press", "row": "Barbell Row",
        "dumbbell shoulder press": "DB Shoulder Press", "shoulder press": "DB Shoulder Press",
        "dumbbell biceps curl": "DB Biceps Curl", "biceps curl": "DB Biceps Curl",
    ]

    /// Garmin `exercise_category` → muscles, for any exercise that is not a catalogue lift.
    public static let categories: [String: [MuscleWeight]] = [
        "BENCH_PRESS": [p(.chest), s(.triceps)], "FLYE": [p(.chest)], "PUSH_UP": [p(.chest), s(.triceps)],
        "ROW": [p(.upperBack), s(.lats)], "PULL_UP": [p(.lats), s(.biceps)], "SHOULDER_PRESS": [p(.shoulders)],
        "LATERAL_RAISE": [p(.shoulders)], "SHRUG": [p(.traps)], "CURL": [p(.biceps)], "TRICEPS_EXTENSION": [p(.triceps)],
        "SQUAT": [p(.quads), s(.glutes)], "LUNGE": [p(.quads), s(.glutes)],
        "DEADLIFT": [p(.hamstrings), s(.glutes), s(.lowerBack)],
        "HIP_RAISE": [p(.glutes)], "CALF_RAISE": [p(.calves)], "PLANK": [p(.core)], "CORE": [p(.core)],
        "CRUNCH": [p(.core)], "HIP_STABILITY": [p(.core)], "SIT_UP": [p(.core)],
    ]

    private static let byNormalized: [String: String] = {
        var d = Dictionary(exercises.keys.map { (Progression.normalizedName($0), $0) }, uniquingKeysWith: { a, _ in a })
        for (k, v) in exerciseAliases { d[k] = v }
        return d
    }()
    private static let categoryByNormalized: [String: String] =
        Dictionary(categories.keys.map { (Progression.normalizedName($0), $0) }, uniquingKeysWith: { a, _ in a })
    /// Garmin exercise name → catalogue lift, from `ExerciseAliases` (cardio aliases drop out).
    public static let garminNames: [String: String] = {
        var d: [String: String] = [:]
        for (plan, alias) in ExerciseAliases.byPlanName where exercises[plan] != nil {
            for name in alias.garminNames { d[name] = plan }
        }
        return d
    }()
    private static let garminByNormalized: [String: String] =
        Dictionary(garminNames.map { (Progression.normalizedName($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })

    /// The catalogue lift a plan/logger exerciseKey names, or nil.
    public static func catalogueKey(_ exerciseKey: String) -> String? { byNormalized[Progression.normalizedName(exerciseKey)] }

    public static func weights(forExercise exerciseKey: String) -> [MuscleWeight]? {
        catalogueKey(exerciseKey).flatMap { exercises[$0] }
    }

    public static func weights(forCategory category: String?) -> [MuscleWeight]? {
        categoryByNormalized[Progression.normalizedName(category ?? "")].flatMap { categories[$0] }
    }

    /// A Garmin set: its named catalogue lift first, else its category.
    public static func weights(forGarminName name: String?, category: String?) -> [MuscleWeight]? {
        if let lift = garminByNormalized[Progression.normalizedName(name ?? "")] { return exercises[lift] }
        return weights(forCategory: category)
    }

    /// Display names, primary first (the logger preview / library row).
    public static func displayNames(_ weights: [MuscleWeight]?) -> [String] { (weights ?? []).map(\.muscle.displayName) }
}

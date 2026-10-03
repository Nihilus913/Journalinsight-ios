import Foundation
import JICore

/// W-B38-B B-10 — what the exercise library shows for one exercise (scout §4 q3; Toby
/// 2026-10-03: targeted muscles, no animation). Descriptive content only — no numbers.
public nonisolated struct ExercisePreview: Hashable, Sendable {
    public var systemImage: String
    /// Primary muscle first. Empty = not described (drawn as words, never hidden).
    public var muscles: [String]
    public var equipment: String?
    /// One-line form cue; nil for an exercise we have no cue for (never invented).
    public var cue: String?

    public var muscleLine: String { muscles.isEmpty ? "Muscles not described yet" : muscles.joined(separator: " · ") }
    public var primaryMuscle: String { muscles.first ?? "Other" }
}

/// One library row: the catalogue entry + its preview.
public nonisolated struct ExerciseLibraryEntry: Hashable, Sendable, Identifiable {
    public var option: ExerciseOption
    public var preview: ExercisePreview
    public var id: String { option.key }
}

/// The library's descriptions for the ONE catalogue (`WorkoutExerciseCatalogue.known`); any other
/// exercise (a library extra) gets its muscles from its Garmin category and no cue.
public nonisolated enum ExerciseLibrary {
    static let described: [String: ExercisePreview] = [
        "Barbell Bench Press": .init(systemImage: "figure.strengthtraining.traditional", muscles: ["Chest", "Triceps", "Front delts"],
                                     equipment: "Barbell + bench", cue: "Shoulder blades pinned, bar to mid-chest, feet driving."),
        "Barbell Row": .init(systemImage: "figure.strengthtraining.traditional", muscles: ["Upper back", "Lats", "Biceps"],
                             equipment: "Barbell", cue: "Hinge to ~45°, pull the bar to the lower ribs, no torso swing."),
        "DB Shoulder Press": .init(systemImage: "dumbbell.fill", muscles: ["Shoulders", "Triceps"],
                                   equipment: "Dumbbells", cue: "Ribs down, press straight up, stop short of lockout clash."),
        "DB Biceps Curl": .init(systemImage: "dumbbell.fill", muscles: ["Biceps", "Forearms"],
                                equipment: "Dumbbells", cue: "Elbows still at your sides, lower slowly."),
        "Diamond Push-Up": .init(systemImage: "figure.cross.training", muscles: ["Triceps", "Chest"],
                                 equipment: "Bodyweight", cue: "Hands under the sternum, body one straight line."),
        "Dead Bug": .init(systemImage: "figure.core.training", muscles: ["Core"],
                          equipment: "Bodyweight", cue: "Low back flat on the floor, opposite arm and leg move slowly."),
        "Plank": .init(systemImage: "figure.core.training", muscles: ["Core", "Shoulders"],
                       equipment: "Bodyweight", cue: "Squeeze glutes, ribs down, breathe — stop when the hips sag."),
        "KB Overhead Triceps Extension": .init(systemImage: "dumbbell.fill", muscles: ["Triceps"],
                                               equipment: "Kettlebell", cue: "Elbows point forward, lower behind the head under control."),
        "Ab Roller": .init(systemImage: "figure.core.training", muscles: ["Core", "Lats"],
                           equipment: "Ab wheel", cue: "Roll only as far as the low back stays neutral."),
    ]

    /// Garmin category → muscles, for exercises the library has no description of.
    static let categoryMuscles: [String: [String]] = [
        "BENCH_PRESS": ["Chest", "Triceps"], "FLYE": ["Chest"], "PUSH_UP": ["Chest", "Triceps"],
        "ROW": ["Upper back", "Lats"], "PULL_UP": ["Lats", "Biceps"], "SHOULDER_PRESS": ["Shoulders"],
        "LATERAL_RAISE": ["Shoulders"], "SHRUG": ["Traps"], "CURL": ["Biceps"], "TRICEPS_EXTENSION": ["Triceps"],
        "SQUAT": ["Quads", "Glutes"], "LUNGE": ["Quads", "Glutes"], "DEADLIFT": ["Hamstrings", "Glutes", "Back"],
        "HIP_RAISE": ["Glutes"], "CALF_RAISE": ["Calves"], "PLANK": ["Core"], "CORE": ["Core"],
        "CRUNCH": ["Core"], "HIP_STABILITY": ["Core"], "SIT_UP": ["Core"],
    ]

    static let categoryEquipment: [String: String] = ["PUSH_UP": "Bodyweight", "PLANK": "Bodyweight", "PULL_UP": "Bar"]

    public static func preview(for option: ExerciseOption) -> ExercisePreview {
        if let known = described[option.key] { return known }
        let muscles = categoryMuscles[option.garminCategory] ?? []
        let core = muscles.first == "Core"
        return ExercisePreview(systemImage: core ? "figure.core.training" : "figure.strengthtraining.traditional",
                               muscles: muscles, equipment: categoryEquipment[option.garminCategory], cue: nil)
    }
}

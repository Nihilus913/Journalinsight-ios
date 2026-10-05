import Foundation
import JICore
import JICompute

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
        "Barbell Bench Press": .init(systemImage: "figure.strengthtraining.traditional", muscles: [],
                                     equipment: "Barbell + bench", cue: "Shoulder blades pinned, bar to mid-chest, feet driving."),
        "Barbell Row": .init(systemImage: "figure.strengthtraining.traditional", muscles: [],
                             equipment: "Barbell", cue: "Hinge to ~45°, pull the bar to the lower ribs, no torso swing."),
        "DB Shoulder Press": .init(systemImage: "dumbbell.fill", muscles: [],
                                   equipment: "Dumbbells", cue: "Ribs down, press straight up, stop short of lockout clash."),
        "DB Biceps Curl": .init(systemImage: "dumbbell.fill", muscles: [],
                                equipment: "Dumbbells", cue: "Elbows still at your sides, lower slowly."),
        "Diamond Push-Up": .init(systemImage: "figure.cross.training", muscles: [],
                                 equipment: "Bodyweight", cue: "Hands under the sternum, body one straight line."),
        "Dead Bug": .init(systemImage: "figure.core.training", muscles: [],
                          equipment: "Bodyweight", cue: "Low back flat on the floor, opposite arm and leg move slowly."),
        "Plank": .init(systemImage: "figure.core.training", muscles: [],
                       equipment: "Bodyweight", cue: "Squeeze glutes, ribs down, breathe — stop when the hips sag."),
        "KB Overhead Triceps Extension": .init(systemImage: "dumbbell.fill", muscles: [],
                                               equipment: "Kettlebell", cue: "Elbows point forward, lower behind the head under control."),
        "Ab Roller": .init(systemImage: "figure.core.training", muscles: [],
                           equipment: "Ab wheel", cue: "Roll only as far as the low back stays neutral."),
    ]

    static let categoryEquipment: [String: String] = ["PUSH_UP": "Bodyweight", "PLANK": "Bodyweight", "PULL_UP": "Bar"]

    /// B-90 p1: muscles come from the ONE table (`JICompute.MuscleMap`) — the catalogue lift's own
    /// row (the logger's preview, so both name the same targets), else its Garmin category's row.
    public static func preview(for option: ExerciseOption) -> ExercisePreview {
        if var known = described[option.key] {
            known.muscles = StrengthMuscles.targets(for: option.key) ?? []
            return known
        }
        let muscles = MuscleMap.displayNames(MuscleMap.weights(forCategory: option.garminCategory))
        let core = muscles.first == "Core"
        return ExercisePreview(systemImage: core ? "figure.core.training" : "figure.strengthtraining.traditional",
                               muscles: muscles, equipment: categoryEquipment[option.garminCategory], cue: nil)
    }
}

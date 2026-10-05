import Foundation
import Testing
import JICore
@testable import JIFeatures

/// B-90 p1 exit: moving the logger preview and the library onto `MuscleMap` changes no shown text.
/// The expected strings are the pre-B-90 `StrengthMuscles.targets` / `ExerciseLibrary.categoryMuscles`
/// values, verbatim — except DEADLIFT's ambiguous "Back", now "Lower back" (one vocabulary).
@MainActor @Suite struct B90PreviewUnchangedTests {
    static let loggerBefore: [String: [String]] = [
        "Barbell Bench Press": ["Chest", "Front delts", "Triceps"], "bench press": ["Chest", "Front delts", "Triceps"],
        "bench": ["Chest", "Front delts", "Triceps"], "Barbell Row": ["Upper back", "Lats", "Biceps"], "row": ["Upper back", "Lats", "Biceps"],
        "DB Shoulder Press": ["Shoulders", "Triceps"], "dumbbell shoulder press": ["Shoulders", "Triceps"], "shoulder press": ["Shoulders", "Triceps"],
        "DB Biceps Curl": ["Biceps", "Forearms"], "dumbbell biceps curl": ["Biceps", "Forearms"], "biceps curl": ["Biceps", "Forearms"],
        "Diamond Push-Up": ["Triceps", "Chest"], "diamond push up": ["Triceps", "Chest"], "Dead Bug": ["Deep core", "Hip flexors"],
        "Plank": ["Core", "Shoulders"], "KB Overhead Triceps Extension": ["Triceps"], "Ab Roller": ["Abs", "Lats"],
    ]
    static let categoryBefore: [String: [String]] = [
        "BENCH_PRESS": ["Chest", "Triceps"], "FLYE": ["Chest"], "PUSH_UP": ["Chest", "Triceps"],
        "ROW": ["Upper back", "Lats"], "PULL_UP": ["Lats", "Biceps"], "SHOULDER_PRESS": ["Shoulders"],
        "LATERAL_RAISE": ["Shoulders"], "SHRUG": ["Traps"], "CURL": ["Biceps"], "TRICEPS_EXTENSION": ["Triceps"],
        "SQUAT": ["Quads", "Glutes"], "LUNGE": ["Quads", "Glutes"], "DEADLIFT": ["Hamstrings", "Glutes", "Lower back"],
        "HIP_RAISE": ["Glutes"], "CALF_RAISE": ["Calves"], "PLANK": ["Core"], "CORE": ["Core"],
        "CRUNCH": ["Core"], "HIP_STABILITY": ["Core"], "SIT_UP": ["Core"],
    ]

    @Test func loggerPreviewUnchanged() {
        for (key, muscles) in Self.loggerBefore { #expect(StrengthMuscles.targets(for: key) == muscles, "\(key)") }
        #expect(StrengthMuscles.targets(for: "Jump Rope") == nil)
        #expect(StrengthMuscles.targets(for: "Mystery") == nil)
    }

    @Test func libraryRowsAndGroupsUnchanged() {
        for option in WorkoutExerciseCatalogue.known {
            #expect(ExerciseLibrary.preview(for: option).muscles == Self.loggerBefore[option.key], "\(option.key)")
        }
        for (cat, muscles) in Self.categoryBefore {
            let p = ExerciseLibrary.preview(for: ExerciseOption(key: "Extra \(cat)", garminCategory: cat, garminExercise: nil))
            #expect(p.muscles == muscles, "\(cat)")
        }
        let groups = ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known).groups.map(\.title)
        #expect(groups == ["Abs", "Biceps", "Chest", "Core", "Deep core", "Shoulders", "Triceps", "Upper back"])
    }
}

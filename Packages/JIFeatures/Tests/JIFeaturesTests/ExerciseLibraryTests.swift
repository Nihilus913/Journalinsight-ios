import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B38-B B-10 — the exercise library browses the ONE catalogue (`WorkoutExerciseCatalogue`)
/// with a preview per exercise (SF Symbol, targeted muscles, equipment, one-line cue) and a pick
/// that adds the exercise to the running session.
@MainActor
struct ExerciseLibraryTests {
    @Test func everyKnownExerciseHasAPreviewWithMusclesAndACue() {
        for option in WorkoutExerciseCatalogue.known {
            let p = ExerciseLibrary.preview(for: option)
            #expect(!p.muscles.isEmpty, "\(option.key) names no muscle")
            #expect(p.cue != nil, "\(option.key) has no cue")
            #expect(!p.systemImage.isEmpty)
            #expect(p.equipment != nil)
        }
    }

    @Test func unknownExerciseFallsBackToItsGarminCategoryAndNamesNoCue() {
        let row = ExerciseOption(key: "Cable Fly", garminCategory: "FLYE", garminExercise: "CABLE_CROSSOVER")
        let p = ExerciseLibrary.preview(for: row)
        #expect(p.muscles == ["Chest"])
        #expect(p.cue == nil)        // never an invented coaching cue
        let odd = ExerciseLibrary.preview(for: ExerciseOption(key: "Mystery", garminCategory: "UNMAPPED", garminExercise: nil))
        #expect(odd.muscles.isEmpty)
        #expect(odd.muscleLine == "Muscles not described yet")
    }

    @Test func libraryListsTheCatalogueOnceWithExtrasFromTemplates() {
        let extra = ExerciseOption(key: "Cable Fly", garminCategory: "FLYE", garminExercise: nil)
        let model = ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known + [extra, WorkoutExerciseCatalogue.known[0]])
        #expect(model.entries.count == WorkoutExerciseCatalogue.known.count + 1)
        #expect(model.entries.map(\.option.key).contains("Cable Fly"))
    }

    @Test func searchMatchesNameOrMuscleCaseInsensitively() {
        let model = ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known)
        model.query = "bench"
        #expect(model.filtered.map(\.option.key) == ["Barbell Bench Press"])
        model.query = "CORE"
        #expect(model.filtered.map(\.option.key).contains("Plank"))
        #expect(!model.filtered.map(\.option.key).contains("Barbell Row"))
        model.query = "  "
        #expect(model.filtered.count == WorkoutExerciseCatalogue.known.count)
    }

    @Test func groupsAreByPrimaryMuscleInStableOrder() {
        let model = ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known)
        let titles = model.groups.map(\.title)
        #expect(titles == titles.sorted())
        #expect(model.groups.flatMap(\.entries).count == WorkoutExerciseCatalogue.known.count)
    }

    @Test func pickHandsTheExerciseToTheSessionOnce() {
        var picked: [String] = []
        let model = ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known) { picked.append($0.key) }
        model.pick(model.entries[1])
        #expect(picked == [WorkoutExerciseCatalogue.known[1].key])
        #expect(model.lastPicked == WorkoutExerciseCatalogue.known[1].key)
    }
}

/// B-10 exit: a library pick adds the exercise to the running logger session (once).
@MainActor
struct ExerciseLibraryPickTests {
    @Test func pickAddsTheExerciseToTheLoggerOnce() throws {
        let store = StrengthSessionLogStore(db: try AppDatabase.inMemory())
        let log = StrengthLogViewModel(lifts: [], sessionId: nil, sessionName: nil, store: store, outbox: nil, provider: nil,
                                       prefs: nil, today: { "2026-10-05" })
        let library = ExerciseLibraryViewModel(options: WorkoutExerciseCatalogue.known) { log.addExercise($0) }
        let plank = try #require(library.entries.first { $0.option.key == "Plank" })
        library.pick(plank)
        library.pick(plank)
        #expect(log.cards.map(\.lift.exerciseKey) == ["Plank"])
        #expect(log.cards.first?.lift.nextKg == nil)   // no invented weight for a library extra
        #expect(log.logSet(exerciseKey: "Plank", weightKg: nil, reps: 30) != nil)
    }
}

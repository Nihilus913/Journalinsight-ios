import Foundation
import Testing
import JICore
@testable import JIFeatures

/// RG-54: Decide's lift hint names the exercise and shows whole kg ("Bench press 50 kg"); the
/// Training hero rows use the same format (never "50.0 kg" / "12.0 kg").
@Suite struct RG54LiftFormatTests {
    static func lift(_ name: String, _ state: ProgressionState, now: Double, next: Double) -> LiftProgression {
        LiftProgression(exerciseId: 1, name: name, sessionName: "Day 2 Full Upper", currentKg: now, nextKg: next, state: state, sets: 3)
    }

    static func ex(_ id: Int, _ name: String, _ kg: Double) -> Exercise {
        Exercise(exerciseId: id, sessionName: "Full Upper", exerciseName: name, sets: 3, repsTarget: nil,
                 currentWeightKg: kg, progressionStepKg: nil, sessionId: 7)
    }

    @Test func wholeKgDropsTheDecimal() {
        #expect(jiKg(50.0) == "50")
        #expect(jiKg(12) == "12")
        #expect(jiKg(52.5) == "52.5")
        #expect(jiKg(1.25) == "1.25")
    }

    @Test func decideLiftAndHeroHintNameTheExercise() throws {
        let lift = try #require(decideSessionLift([Self.lift("Bench press", .notYet, now: 50, next: 50)]))
        #expect(lift.kg == "50 kg")
        #expect(decideHeroLiftHint(lift, name: "Bench press") == "Bench press 50 kg")
        let due = try #require(decideSessionLift([Self.lift("Bench press", .due(nextKg: 52.5), now: 50, next: 52.5)]))
        #expect(decideHeroLiftHint(due, name: "Bench press") == "Bench press 52.5 kg ↑")
        #expect(decideHeroLiftHint(lift, name: "  ") == "50 kg")
    }

    @Test func trainingHeroRowsUseWholeKg() {
        let ex = [Self.ex(1, "Bench press", 50), Self.ex(2, "DB Curl", 12), Self.ex(3, "Incline", 22.5)]
        let rows = trainingHeroRows(exercises: ex, session: PlannedSession(id: 7, name: "Full Upper", weekday: 2))
        #expect(rows.map(\.load) == ["50 kg · 3 sets", "12 kg · 3 sets", "22.5 kg · 3 sets"])
    }
}

import Foundation
import Testing
import JICore
@testable import JIPersistence

@Test func entriesListsEveryStoredExercise() {
    let d = UserDefaults(suiteName: "test.strength.\(UUID().uuidString)")!
    let s = StrengthStateStore(defaults: d)
    #expect(s.entries().isEmpty)
    s.saveLocal(exerciseId: 2, exerciseName: "Bent-over row", patch: ExerciseUpdate(currentWeightKg: 50, progressionStepKg: 2.5))
    s.saveLocal(exerciseId: 1, exerciseName: "Bench press", patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5))
    #expect(s.entries().map(\.exerciseName) == ["Bench press", "Bent-over row"])
}

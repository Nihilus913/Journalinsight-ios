import Foundation
import Testing
@testable import JICore

@Test func decodesTrainingDayDetailWithActivitiesAndSets() throws {
    let json = """
    {"date":"2026-09-11","meals":{"total":{"kcal":1000}},
     "activities":[{"activity_id":1,"type":"strength_training","name":"Full Upper","duration_sec":3120,"distance_m":null}],
     "exercise_sets":[
       {"exercise_name":"Barbell Bench Press","exercise_category":"strength","set_number":1,"reps":10,"weight_kg":50.0},
       {"exercise_name":"Barbell Bench Press","exercise_category":"strength","set_number":2,"reps":null,"weight_kg":null}
     ]}
    """
    let day = try JSON.decoder.decode(TrainingDayDetail.self, from: Data(json.utf8))
    #expect(day.date == "2026-09-11")
    #expect(day.activities.count == 1)
    #expect(day.activities[0].name == "Full Upper")
    #expect(day.activities[0].durationSec == 3120)
    #expect(day.exerciseSets.count == 2)
    #expect(day.exerciseSets[1].reps == nil) // never coerced to 0 (CLAUDE.md rule 5)
}

@Test func decodesTrainingDayDetailWithNoActivityOrSets() throws {
    let json = """
    {"date":"2026-09-11","activities":[],"exercise_sets":[]}
    """
    let day = try JSON.decoder.decode(TrainingDayDetail.self, from: Data(json.utf8))
    #expect(day.activities.isEmpty)
    #expect(day.exerciseSets.isEmpty)
}

@Test func decodesExerciseWithFreeTextRepsTarget() throws {
    let json = """
    [
      {"exercise_id":19,"session_name":"Day 1 Full Upper","exercise_name":"Barbell Bench Press","sets":3,"reps_target":"6-12","current_weight_kg":50.0,"progression_step_kg":2.5},
      {"exercise_id":24,"session_name":"Day 1 Full Upper","exercise_name":"Dead Bug","sets":3,"reps_target":"10/side","current_weight_kg":null,"progression_step_kg":null},
      {"exercise_id":30,"session_name":"Day 2 Full Upper","exercise_name":"Plank","sets":3,"reps_target":"45s","current_weight_kg":null,"progression_step_kg":null}
    ]
    """
    let rows = try JSON.decoder.decode([Exercise].self, from: Data(json.utf8))
    #expect(rows[0].repsTarget == "6-12")
    #expect(rows[0].currentWeightKg == 50.0)
    #expect(rows[1].repsTarget == "10/side")
    #expect(rows[1].currentWeightKg == nil) // never coerced to 0
    #expect(rows[2].repsTarget == "45s")
}

@Test func decodesExerciseWithNumericRepsTarget() throws {
    // A handful of wire rows are plain numeric JSON rather than free text.
    let json = """
    [{"exercise_id":21,"session_name":"Day 1 Full Upper","exercise_name":"DB Shoulder Press","sets":3,"reps_target":12,"current_weight_kg":12.0,"progression_step_kg":2.5}]
    """
    let rows = try JSON.decoder.decode([Exercise].self, from: Data(json.utf8))
    #expect(rows[0].repsTarget == "12")
}

// One test per parseRepsTarget branch (Data seam exit criterion).
@Test func parseRepsTargetOnNilReturnsNil() { #expect(parseRepsTarget(nil) == nil) }
@Test func parseRepsTargetOnCleanIntegerReturnsInt() { #expect(parseRepsTarget("12") == 12) }
@Test func parseRepsTargetOnRangeReturnsNil() { #expect(parseRepsTarget("6-12") == nil) }
@Test func parseRepsTargetOnMaxReturnsNil() { #expect(parseRepsTarget("max") == nil) }
@Test func parseRepsTargetOnPerSideReturnsNil() { #expect(parseRepsTarget("10/side") == nil) }
@Test func parseRepsTargetOnSecondsReturnsNil() { #expect(parseRepsTarget("45s") == nil) }

@Test func exerciseUpdateEncodesSnakeCaseWireBody() throws {
    // Plain JSONEncoder() (no .convertToSnakeCase), matching HubClient.post's own body encoding —
    // ExerciseUpdate must already be snake_case via its own CodingKeys.
    let update = ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5, sets: 3, repsTarget: 10)
    let data = try JSONEncoder().encode(update)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((obj["current_weight_kg"] as? Double) == 52.5)
    #expect((obj["progression_step_kg"] as? Double) == 2.5)
    #expect((obj["reps_target"] as? Int) == 10)
    #expect(obj["currentWeightKg"] == nil)
}

@Test func exerciseUpdateResultDecodes() throws {
    let json = """
    {"exercise_id":19,"updated":true}
    """
    let result = try JSON.decoder.decode(ExerciseUpdateResult.self, from: Data(json.utf8))
    #expect(result.exerciseId == 19)
    #expect(result.updated)
}

@Test func mockProviderServesTrainingFixtures() async throws {
    let provider = MockDataProvider()
    let day = try await provider.trainingDay(date: "2026-09-11")
    #expect(day.date == "2026-09-11")
    let exercises = try await provider.exercises()
    #expect(exercises.isEmpty == false)
    #expect(exercises.contains { $0.exerciseName == "Barbell Bench Press" })
}

@Test func mockProviderUpdateExerciseIsANoOpSuccess() async throws {
    let result = try await MockDataProvider().updateExercise(exerciseId: 19, patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5))
    #expect(result.exerciseId == 19)
    #expect(result.updated)
}

import Foundation
import Testing
import JICore
@testable import JIHub

/// Exercises `HubDataProvider`'s `TrainingProviding` conformance (`HubDataProvider+Training.swift`)
/// via its `trainingSecrets`/`trainingSession` test seams — see that file's doc comment for why
/// `HubDataProvider.client` itself is out of reach here. Merged into `HubClientTests`' own
/// `.serialized` suite convention (`StubURLProtocol`'s process-global state), so these run
/// sequentially with every other `StubURLProtocol`-based test in the target.
extension HubClientTests {
    private func configuredProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let secrets = InMemorySecretStore()
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        try! ConnectionConfigStore(secrets: secrets).save(config)
        HubDataProvider.trainingSecrets = secrets
        HubDataProvider.trainingSession = StubURLProtocol.session()
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func trainingDayDecodesContractFixture() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/training/day/2026-09-11"] = (200, Data("""
        {"date":"2026-09-11","activities":[{"activity_id":1,"type":"strength_training","name":"Full Upper","duration_sec":3000,"distance_m":null}],
         "exercise_sets":[{"exercise_name":"Barbell Bench Press","exercise_category":"strength","set_number":1,"reps":10,"weight_kg":50.0}]}
        """.utf8))
        let provider = configuredProvider()
        let day = try await provider.trainingDay(date: "2026-09-11")
        #expect(day.date == "2026-09-11")
        #expect(day.activities.first?.name == "Full Upper")
        #expect(day.exerciseSets.first?.weightKg == 50.0)
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/training/day/2026-09-11")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func exercisesDecodesContractFixture() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/exercises"] = (200, Data("""
        [{"exercise_id":19,"session_name":"Day 1 Full Upper","exercise_name":"Barbell Bench Press","sets":3,"reps_target":"6-12","current_weight_kg":50.0,"progression_step_kg":2.5}]
        """.utf8))
        let provider = configuredProvider()
        let rows = try await provider.exercises()
        #expect(rows.count == 1)
        #expect(rows[0].exerciseId == 19)
        #expect(rows[0].repsTarget == "6-12")
        #expect(parseRepsTarget(rows[0].repsTarget) == nil) // "6-12" is not a clean integer
    }

    @Test func updateExerciseSendsPatchWithBearerAndDecodesResult() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/exercises/19"] = (200, Data("""
        {"exercise_id":19,"updated":true}
        """.utf8))
        let provider = configuredProvider()
        let result = try await provider.updateExercise(exerciseId: 19, patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5, sets: 3, repsTarget: 10))

        #expect(result.exerciseId == 19)
        #expect(result.updated)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "PATCH")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/exercises/19")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func updateExercisePropagatesNamedHubErrorOn401() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/exercises/19"] = (401, Data("{\"detail\":\"nope\"}".utf8))
        let provider = configuredProvider()
        await #expect(throws: HubError.unauthorized) {
            _ = try await provider.updateExercise(exerciseId: 19, patch: ExerciseUpdate(currentWeightKg: 52.5, progressionStepKg: 2.5))
        }
    }
}

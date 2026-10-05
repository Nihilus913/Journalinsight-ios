import Foundation
import Testing
@testable import JICompute

/// B-90 p1 — the Swift table equals HT `tests/fixtures/muscle_map.json` (the Python twin's export).
@Suite struct MuscleMapTests {
    struct Row: Decodable { let muscle: String; let weight: Double }
    struct Fixture: Decodable {
        let muscles: [String: String]
        let exercises: [String: [Row]]
        let exercise_aliases: [String: String]
        let garmin_names: [String: String]
        let categories: [String: [Row]]
    }

    func fixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "muscle_map", withExtension: "json", subdirectory: "Resources/golden"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func rows(_ w: [MuscleWeight]) -> [String] { w.map { "\($0.muscle.rawValue)=\($0.weight)" } }
    func rows(_ r: [Row]) -> [String] { r.map { "\($0.muscle)=\($0.weight)" } }

    @Test func vocabularyMatchesPython() throws {
        let f = try fixture()
        #expect(Dictionary(uniqueKeysWithValues: Muscle.allCases.map { ($0.rawValue, $0.displayName) }) == f.muscles)
    }

    @Test func tablesMatchPythonExactly() throws {
        let f = try fixture()
        #expect(Set(MuscleMap.exercises.keys) == Set(f.exercises.keys))
        for (k, v) in f.exercises { #expect(rows(MuscleMap.exercises[k] ?? []) == rows(v), "\(k)") }
        #expect(Set(MuscleMap.categories.keys) == Set(f.categories.keys))
        for (k, v) in f.categories { #expect(rows(MuscleMap.categories[k] ?? []) == rows(v), "\(k)") }
        #expect(MuscleMap.exerciseAliases == f.exercise_aliases)
        #expect(MuscleMap.garminNames == f.garmin_names)
    }

    @Test func primaryFirstAndWeightsValid() {
        for (k, w) in Array(MuscleMap.exercises) + Array(MuscleMap.categories) {
            #expect(w.first?.weight == MuscleMap.primary, "\(k)")
            #expect(w.allSatisfy { $0.weight == MuscleMap.primary || $0.weight == MuscleMap.secondary }, "\(k)")
            #expect(Set(w.map(\.muscle)).count == w.count, "\(k)")
        }
    }

    @Test func lookupsByKeyAliasGarminNameAndCategory() {
        #expect(MuscleMap.displayNames(MuscleMap.weights(forExercise: "bench")) == ["Chest", "Front delts", "Triceps"])
        #expect(MuscleMap.displayNames(MuscleMap.weights(forExercise: "DEAD_BUG")) == ["Deep core", "Hip flexors"])
        #expect(MuscleMap.weights(forGarminName: "BARBELL_ROLLOUT", category: "CORE") == MuscleMap.exercises["Ab Roller"])
        #expect(MuscleMap.weights(forGarminName: "BACK_SQUAT", category: "SQUAT") == MuscleMap.categories["SQUAT"])
        #expect(MuscleMap.weights(forExercise: "Mystery") == nil)
        #expect(MuscleMap.weights(forCategory: nil) == nil)
        #expect(MuscleMap.displayNames(nil).isEmpty)
    }

    @Test func parityRegistryEntry() {
        #expect(ParityRegistry.source(for: "muscle_map") == .computed)
        #expect(ParityRegistry.implementation(for: "muscle_map") == "JICompute.MuscleMap")
    }
}

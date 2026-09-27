import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

nonisolated final class ProgressionFakeProvider: TrainingProviding, @unchecked Sendable {
    var rows: [Exercise]
    var days: [String: [DayExerciseSet]]
    var dayCalls: [String] = []
    init(rows: [Exercise], days: [String: [DayExerciseSet]]) { self.rows = rows; self.days = days }
    func trainingDay(date: String) async throws -> TrainingDayDetail {
        dayCalls.append(date)
        return TrainingDayDetail(date: date, activities: [], exerciseSets: days[date] ?? [])
    }
    func exercises() async throws -> [Exercise] { rows }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult { ExerciseUpdateResult(exerciseId: exerciseId, updated: true) }
}

@MainActor
struct ProgressionServiceTests {
    static let rows = [
        Exercise(exerciseId: 1, sessionName: "Day 2 Full Upper", exerciseName: "Bench press", sets: 3, repsTarget: "8",
                 currentWeightKg: 50, progressionStepKg: 2.5, weekday: 2, sessionId: 12),
        Exercise(exerciseId: 2, sessionName: "Day 2 Full Upper", exerciseName: "Bent-over row", sets: 3, repsTarget: "8",
                 currentWeightKg: 50, progressionStepKg: 2.5, weekday: 2, sessionId: 12),
    ]
    static func s(_ name: String, _ n: Int, _ reps: Int, _ kg: Double) -> DayExerciseSet {
        DayExerciseSet(exerciseName: name, exerciseCategory: nil, setNumber: n, reps: reps, weightKg: kg)
    }

    @Test func lastOccurrenceIsStrictlyBeforeToday() {
        #expect(lastOccurrence(ofWeekday: 2, before: "2026-09-23") == "2026-09-16")   // Wed → last Wed
        #expect(lastOccurrence(ofWeekday: 0, before: "2026-09-23") == "2026-09-21")   // Mon
        #expect(lastOccurrence(ofWeekday: 7, before: "2026-09-23") == nil)
    }

    @Test func serviceReadsLastSessionAndMarksDue() async throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        let provider = ProgressionFakeProvider(rows: Self.rows, days: [
            "2026-09-16": [Self.s("BENCH_PRESS", 1, 8, 50), Self.s("BENCH_PRESS", 2, 8, 50), Self.s("BENCH_PRESS", 3, 8, 50),
                           Self.s("Bent-over row", 1, 8, 50), Self.s("Bent-over row", 2, 6, 50), Self.s("Bent-over row", 3, 8, 50)],
        ])
        let svc = ProgressionService(provider: provider, cache: cache, strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "prog.\(UUID())")),
                                     prefs: nil, today: { "2026-09-23" })
        await svc.refresh()
        #expect(svc.lift(named: "Bench press")?.isDue == true)
        #expect(svc.lift(named: "Bench press")?.nextKg == 52.5)
        #expect(svc.lift(named: "Bent-over row")?.state == .notYet)
        #expect(svc.lifts(forSession: "Day 2 Full Upper").count == 2)
        await svc.refreshIfNeeded()
        #expect(provider.dayCalls == ["2026-09-16"])                 // same day → no refetch; cached day not refetched
    }

    @Test func autoSuggestOffUsesLastLifted() async throws {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        try prefs.set(progressionAutoSuggestKey, false)
        #expect(progressionAutoSuggest(prefs: prefs) == false)
        #expect(progressionAutoSuggest(prefs: nil) == true)
        let out = liftProgressions(exercises: Self.rows, entries: [],
                                   lastSessionSets: ["Day 2 Full Upper": [LoggedSet(exerciseName: "Bench press", category: nil, setNumber: 1, reps: 8, weightKg: 52.5)]],
                                   autoSuggest: false)
        #expect(out.first?.state == .manual(lastLiftedKg: 52.5) && out.first?.nextKg == 52.5)
    }

    @Test func localStrengthStateOverridesThePlanRow() {
        let entry = StrengthStateEntry(exerciseId: 1, exerciseName: "Bench press", currentWeightKg: 52.5, progressionStepKg: 2.5,
                                       sets: 3, repsTarget: 8, updatedAt: "2026-09-20T10:00:00Z", synced: false)
        let out = liftProgressions(exercises: Self.rows, entries: [entry], lastSessionSets: [:], autoSuggest: true)
        #expect(out.first?.currentKg == 52.5)
        #expect(out.first?.state == .noSession)
        #expect(out.first?.nextKg == 52.5)
    }

    @Test func noProviderNoCacheIsEmptyNotInvented() async throws {
        let svc = ProgressionService(provider: nil, cache: OfflineCache(db: try AppDatabase.inMemory()),
                                     strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "prog.\(UUID())")), prefs: nil, today: { "2026-09-23" })
        await svc.refresh()
        #expect(svc.lifts.isEmpty)
    }
}

// JournalInsightTests/WorkoutEntryTests.swift
import Testing
import Foundation
@testable import JournalInsight

@Suite("WorkoutEntryTests")
struct WorkoutEntryTests {

    @Test("WorkoutEntry initialises with defaults")
    func defaultInit() {
        let entry = WorkoutEntry(date: .now, source: .manual, durationSec: 3600)
        #expect(entry.exercises.isEmpty)
        #expect(entry.notes == nil)
        #expect(entry.garminActivityId == nil)
        #expect(entry.healthKitWorkoutId == nil)
    }

    @Test("WorkoutSource raw values are stable")
    func workoutSourceRawValues() {
        #expect(WorkoutSource.manual.rawValue == "manual")
        #expect(WorkoutSource.healthKit.rawValue == "healthKit")
        #expect(WorkoutSource.garmin.rawValue == "garmin")
    }

    @Test("LoggedExercise stores all fields")
    func loggedExercise() {
        let ex = LoggedExercise(name: "Bench Press", sets: 3, reps: 8, weightKg: 40.0, garminExerciseName: "BENCH_PRESS")
        #expect(ex.name == "Bench Press")
        #expect(ex.sets == 3)
        #expect(ex.reps == 8)
        #expect(ex.weightKg == 40.0)
        #expect(ex.garminExerciseName == "BENCH_PRESS")
    }

    @Test("exercises round-trip through exercisesData")
    func exercisesRoundTrip() {
        let entry = WorkoutEntry(date: .now, source: .manual, durationSec: 3600)
        let ex = LoggedExercise(name: "Squat", sets: 4, reps: 6, weightKg: 80.0, garminExerciseName: "SQUAT")
        entry.exercises = [ex]
        let retrieved = entry.exercises
        #expect(retrieved.count == 1)
        #expect(retrieved.first == ex)
        #expect(entry.exercisesData.isEmpty == false)
    }
}

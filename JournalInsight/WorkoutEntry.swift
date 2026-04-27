// JournalInsight/WorkoutEntry.swift
import Foundation
import SwiftData

struct LoggedExercise: Codable, Equatable {
    var name: String
    var sets: Int
    var reps: Int
    var weightKg: Double?
    var garminExerciseName: String?
}

enum WorkoutSource: String, Codable {
    case manual, healthKit, garmin
}

@Model
class WorkoutEntry {
    var date: Date
    var source: WorkoutSource
    var durationSec: Int
    var exercisesData: Data
    var notes: String?
    @Attribute(.unique) var garminActivityId: Int64?
    @Attribute(.unique) var healthKitWorkoutId: UUID?

    var exercises: [LoggedExercise] {
        get {
            (try? JSONDecoder().decode([LoggedExercise].self, from: exercisesData)) ?? []
        }
        set {
            exercisesData = try! JSONEncoder().encode(newValue)
        }
    }

    init(date: Date, source: WorkoutSource, durationSec: Int,
         exercises: [LoggedExercise] = [],
         notes: String? = nil,
         garminActivityId: Int64? = nil,
         healthKitWorkoutId: UUID? = nil) {
        self.date = date
        self.source = source
        self.durationSec = durationSec
        self.exercisesData = try! JSONEncoder().encode(exercises)
        self.notes = notes
        self.garminActivityId = garminActivityId
        self.healthKitWorkoutId = healthKitWorkoutId
    }
}

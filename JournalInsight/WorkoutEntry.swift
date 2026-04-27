// JournalInsight/WorkoutEntry.swift
import Foundation
import SwiftData
import SwiftUI

struct LoggedExercise: Codable, Equatable {
    var name: String
    var sets: Int
    var reps: Int
    var weightKg: Double?
    var garminExerciseName: String?  // SP4: validated Garmin catalogue name
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
            exercisesData = (try? JSONEncoder().encode(newValue)) ?? Data()
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
        self.exercisesData = (try? JSONEncoder().encode(exercises)) ?? Data()
        self.notes = notes
        self.garminActivityId = garminActivityId
        self.healthKitWorkoutId = healthKitWorkoutId
    }
}

extension WorkoutSource {
    var icon: String {
        switch self {
        case .manual:    return "pencil"
        case .healthKit: return "heart.fill"
        case .garmin:    return "applewatch"
        }
    }

    var color: Color {
        switch self {
        case .manual:    return .orange
        case .healthKit: return .red
        case .garmin:    return .blue
        }
    }
}

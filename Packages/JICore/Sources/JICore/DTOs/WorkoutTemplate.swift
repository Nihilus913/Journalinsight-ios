/// B-37-L1 (P-training) — `GET /api/v1/planning/workout-templates` wire contract (Wave Card B-37
/// ## Contract; `app/planning/models.py::WorkoutTemplateOut`). One row per `plan.workout_template`;
/// `steps` is the ordered cardio prescription the WorkoutKit builder (`JIWorkouts.WorkoutBuilder`)
/// and `scripts/create_running_workout.py` (Garmin) both read. Snake_case keys via `JSON.decoder`.
public struct WorkoutTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { templateId }
    public var templateId: Int
    public var name: String
    /// `running` today; the builder maps it onto `HKWorkoutActivityType`.
    public var activity: String
    public var location: WorkoutLocation
    /// Python weekday ints (Mon = 0) the plan puts this template on, or `[]` when unscheduled.
    public var weekdays: [Int]
    public var steps: [WorkoutStep]
    /// ISO-8601 timestamp, kept as a plain string (JICore convention, see `JSON.swift`).
    public var updatedAt: String

    public init(templateId: Int, name: String, activity: String, location: WorkoutLocation, weekdays: [Int], steps: [WorkoutStep], updatedAt: String) {
        self.templateId = templateId; self.name = name; self.activity = activity; self.location = location
        self.weekdays = weekdays; self.steps = steps; self.updatedAt = updatedAt
    }
}

public enum WorkoutLocation: String, Codable, Sendable, CaseIterable {
    case outdoor, indoor
}

public enum WorkoutStepPurpose: String, Codable, Sendable, CaseIterable {
    case warmup, work, recovery, cooldown
}

/// One prescription step. A `work` step immediately followed by a `recovery` step with the same
/// `repeat` n > 1 is one interval block of n iterations (Contract rule); every other step has
/// `repeat == 1`. `hrLo…hrHi` is an absolute-bpm alert range (never a zone), capped at 175
/// everywhere (`project_docs_map` AWU zones — the builder asserts it).
public struct WorkoutStep: Codable, Sendable, Equatable {
    public var purpose: WorkoutStepPurpose
    public var seconds: Int
    public var hrLo: Int
    public var hrHi: Int
    public var `repeat`: Int

    public init(purpose: WorkoutStepPurpose, seconds: Int, hrLo: Int, hrHi: Int, repeat n: Int = 1) {
        self.purpose = purpose; self.seconds = seconds; self.hrLo = hrLo; self.hrHi = hrHi; self.repeat = n
    }
}

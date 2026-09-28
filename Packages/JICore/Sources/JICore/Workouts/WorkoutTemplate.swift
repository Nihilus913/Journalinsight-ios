/// B-37-L1 (P-training) — `GET /api/v1/planning/workout-templates` wire contract (Wave Card B-37
/// ## Contract; `app/planning/models.py::WorkoutTemplateOut`). One row per `plan.workout_template`.
/// Snake_case keys via `JSON.decoder`.
///
/// W-B40 L2 (B-40b-1, spec §2.1 / §3): the row gains `segments` (the canonical, editable
/// prescription — cardio and strength), `description` (Garmin's workout-level free text) and
/// `garmin` (the Garmin Connect counterpart's version stamp). `steps` is the one-wave compat
/// column (= the single running segment when it is time-only + hr_range-only, `[]` otherwise);
/// a B-37 hub sends no `segments` at all, and `effectiveSegments` then derives the running
/// segment from `steps`, so every consumer reads ONE shape.
public struct WorkoutTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { templateId }
    public var templateId: Int
    public var name: String
    /// `running` today; the builder maps it onto `HKWorkoutActivityType`.
    public var activity: String
    public var location: WorkoutLocation
    /// Python weekday ints (Mon = 0) the plan puts this template on, or `[]` when unscheduled.
    /// Read-only here: the weekday is B-45's (`PUT /planning/plan-sessions/{id}`, spec §10.3).
    public var weekdays: [Int]
    public var steps: [WorkoutStep]
    /// W-B40: ordered `[{sport, steps}]`; `[]` from a hub that predates migration 053.
    public var segments: [WorkoutSegment]
    public var description: String?
    /// nil = never linked to a Garmin Connect workout.
    public var garmin: GarminLink?
    /// Spec §10.2: the reduced session the gate prescribes when not cleared (B-49(b)); nil = none.
    public var gatedTemplateId: Int?
    /// ISO-8601 timestamp, kept as a plain string (JICore convention, see `JSON.swift`).
    public var updatedAt: String

    public init(templateId: Int, name: String, activity: String, location: WorkoutLocation, weekdays: [Int], steps: [WorkoutStep], updatedAt: String,
                segments: [WorkoutSegment] = [], description: String? = nil, garmin: GarminLink? = nil, gatedTemplateId: Int? = nil) {
        self.templateId = templateId; self.name = name; self.activity = activity; self.location = location
        self.weekdays = weekdays; self.steps = steps; self.updatedAt = updatedAt
        self.segments = segments; self.description = description; self.garmin = garmin
        self.gatedTemplateId = gatedTemplateId
    }

    private enum CodingKeys: String, CodingKey {
        case templateId, name, activity, location, weekdays, steps, segments, description, garmin, gatedTemplateId, updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        templateId = try c.decode(Int.self, forKey: .templateId)
        name = try c.decode(String.self, forKey: .name)
        activity = try c.decode(String.self, forKey: .activity)
        location = try c.decode(WorkoutLocation.self, forKey: .location)
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        steps = try c.decodeIfPresent([WorkoutStep].self, forKey: .steps) ?? []
        segments = try c.decodeIfPresent([WorkoutSegment].self, forKey: .segments) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description)
        garmin = try c.decodeIfPresent(GarminLink.self, forKey: .garmin)
        gatedTemplateId = try c.decodeIfPresent(Int.self, forKey: .gatedTemplateId)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }

    /// The segments every consumer (builder, library, editor) reads: the hub's `segments`, or —
    /// for a pre-053 row — the compat `steps` as one running segment. Never invents a step.
    public var effectiveSegments: [WorkoutSegment] {
        if !segments.isEmpty || steps.isEmpty { return segments }
        let sport = WorkoutSport(rawValue: activity.lowercased()) ?? .running
        return [WorkoutSegment(sport: sport.isCardio ? sport : .running, steps: steps.map { .cardio(CardioStep($0)) })]
    }

    public var hasStrength: Bool { effectiveSegments.contains { $0.sport == .strength } }
    public var hasCardio: Bool { effectiveSegments.contains { $0.sport.isCardio && !$0.steps.isEmpty } }

    /// Library badge (spec §4: *✓ current* / *outdated* / *not pushed*).
    public var garminState: GarminState {
        guard let garmin else { return .notPushed }
        return garmin.current ? .current : .outdated
    }
}

public enum WorkoutLocation: String, Codable, Sendable, CaseIterable {
    case outdoor, indoor
}

public enum WorkoutStepPurpose: String, Codable, Sendable, CaseIterable {
    case warmup, work, recovery, cooldown
}

/// One B-37 compat prescription step. A `work` step immediately followed by a `recovery` step
/// with the same `repeat` n > 1 is one interval block of n iterations (Contract rule); every other
/// step has `repeat == 1`. `hrLo…hrHi` is an absolute-bpm alert range (never a zone). The Watch
/// builder checks it against the user's own limits (B-57 W4: optional cap, optional Zone 5 avoidance).
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

/// `garmin: {workout_id, current, pushed_at} | null` (spec §3). `current` is the hub's version
/// stamp comparison (`template_updated_at = workout_template.updated_at`), never computed here.
public struct GarminLink: Codable, Sendable, Equatable {
    public var workoutId: Int
    public var current: Bool
    /// nil = imported from Garmin but never pushed back.
    public var pushedAt: String?

    public init(workoutId: Int, current: Bool, pushedAt: String?) {
        self.workoutId = workoutId; self.current = current; self.pushedAt = pushedAt
    }
}

public enum GarminState: Sendable, Equatable {
    case current, outdated, notPushed
}

import Foundation

/// `GET /api/v1/training/day/{date}` — the Training tab's day-strip tap-through detail (oracle:
/// `useTrainingDay.ts` / `TrainingDayDetail` in `mobile/src/data/types.ts`). The real hub envelope
/// also carries a `meals` slice (shared with the nutrition-day endpoint) — irrelevant here and
/// left undecoded; `Decodable` ignores unknown keys by default.
public struct DayActivity: Codable, Sendable, Equatable {
    public var activityId: Int
    public var type: String
    public var name: String?
    public var durationSec: Double?
    public var distanceM: Double?
    public init(activityId: Int, type: String, name: String?, durationSec: Double?, distanceM: Double?) {
        self.activityId = activityId; self.type = type; self.name = name
        self.durationSec = durationSec; self.distanceM = distanceM
    }
}

public struct DayExerciseSet: Codable, Sendable, Equatable {
    public var exerciseName: String?
    public var exerciseCategory: String?
    public var setNumber: Int?
    public var reps: Int?
    public var weightKg: Double?
    public init(exerciseName: String?, exerciseCategory: String?, setNumber: Int?, reps: Int?, weightKg: Double?) {
        self.exerciseName = exerciseName; self.exerciseCategory = exerciseCategory
        self.setNumber = setNumber; self.reps = reps; self.weightKg = weightKg
    }
}

/// B-45 / W-B46 Contract: the `plan.plan_session` row whose `weekday` matches the requested
/// date — the *planned* session, next to the *logged* sets `TrainingDayDetail` already carried.
public struct PlannedSession: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var weekday: Int
    public init(id: Int, name: String, weekday: Int) { self.id = id; self.name = name; self.weekday = weekday }
}

public struct TrainingDayDetail: Codable, Sendable, Equatable {
    public var date: String
    public var activities: [DayActivity]
    public var exerciseSets: [DayExerciseSet]
    /// Optional per the Contract: an older hub simply omits it and the day card falls back to
    /// "logged only" rather than failing to decode the whole response.
    public var plannedSession: PlannedSession?
    public init(date: String, activities: [DayActivity], exerciseSets: [DayExerciseSet], plannedSession: PlannedSession? = nil) {
        self.date = date; self.activities = activities; self.exerciseSets = exerciseSets
        self.plannedSession = plannedSession
    }
}

/// `GET /api/v1/planning/exercises` row (oracle: `Exercise` in `types.ts`). `repsTarget` is a
/// free-text plan column on the wire ('10', '12', 'max', '10/side', '45s' — migration 017), decoded
/// as a raw string even though a handful of rows are numeric-looking, then parsed on demand via
/// `parseRepsTarget` (mirrors `mobile/src/lib/liftFormat.ts`'s own `Number(raw)` / `NaN` guard —
/// never a bare `Int(raw)!` crash on "max").
public struct Exercise: Codable, Sendable, Equatable {
    public var exerciseId: Int
    public var sessionName: String
    public var exerciseName: String
    public var sets: Int?
    public var repsTarget: String?
    public var currentWeightKg: Double?
    public var progressionStepKg: Double?
    /// B-45 / W-B46 Contract: `plan.plan_session.weekday`, Mon = 0 … Sun = 6. Optional twice
    /// over — the column itself is nullable (an unassigned session) AND an old hub omits the key
    /// entirely, which must not fail the decode of the whole plan.
    public var weekday: Int?
    /// The `plan_session` this exercise belongs to — the id `PUT /planning/plan-sessions/{id}`
    /// takes. Optional for the same two reasons.
    public var sessionId: Int?

    public init(
        exerciseId: Int, sessionName: String, exerciseName: String, sets: Int?,
        repsTarget: String?, currentWeightKg: Double?, progressionStepKg: Double?,
        weekday: Int? = nil, sessionId: Int? = nil
    ) {
        self.exerciseId = exerciseId; self.sessionName = sessionName; self.exerciseName = exerciseName
        self.sets = sets; self.repsTarget = repsTarget
        self.currentWeightKg = currentWeightKg; self.progressionStepKg = progressionStepKg
        self.weekday = weekday; self.sessionId = sessionId
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseId, sessionName, exerciseName, sets, repsTarget, currentWeightKg, progressionStepKg
        case weekday, sessionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exerciseId = try c.decode(Int.self, forKey: .exerciseId)
        sessionName = try c.decode(String.self, forKey: .sessionName)
        exerciseName = try c.decode(String.self, forKey: .exerciseName)
        sets = try c.decodeIfPresent(Int.self, forKey: .sets)
        currentWeightKg = try c.decodeIfPresent(Double.self, forKey: .currentWeightKg)
        progressionStepKg = try c.decodeIfPresent(Double.self, forKey: .progressionStepKg)
        weekday = try c.decodeIfPresent(Int.self, forKey: .weekday)
        sessionId = try c.decodeIfPresent(Int.self, forKey: .sessionId)
        // The wire value is free text ("6-12", "max", "10/side", "45s") but a few rows are plain
        // numeric JSON (e.g. "12") — try string first (the common case), fall back to a numeric
        // literal turned into its display string, else nil (never throw on a shape we can't use).
        if let isNull = try? c.decodeNil(forKey: .repsTarget), isNull {
            repsTarget = nil
        } else if let s = try? c.decode(String.self, forKey: .repsTarget) {
            repsTarget = s
        } else if let n = try? c.decode(Double.self, forKey: .repsTarget) {
            repsTarget = n == n.rounded() ? String(Int(n)) : String(n)
        } else {
            repsTarget = nil
        }
    }
}

/// `PATCH /api/v1/planning/exercises/{exercise_id}` body — mirrors `ExerciseUpdate` in `types.ts`.
/// `currentWeightKg`/`progressionStepKg` are always sent (the server overwrites both);
/// `sets`/`repsTarget` are optional — omitted COALESCEs to the existing DB value server-side.
/// Explicit snake_case `CodingKeys`: `HubDataProvider+Training.swift`'s PATCH mirrors
/// `HubClient.post`'s convention of encoding the outgoing body with a plain `JSONEncoder()` (not
/// `JSON.encoder`'s `.convertToSnakeCase`), so this type must already be snake_case on the wire.
public struct ExerciseUpdate: Codable, Sendable, Equatable {
    public var currentWeightKg: Double
    public var progressionStepKg: Double
    public var sets: Int?
    public var repsTarget: Int?
    public init(currentWeightKg: Double, progressionStepKg: Double, sets: Int? = nil, repsTarget: Int? = nil) {
        self.currentWeightKg = currentWeightKg; self.progressionStepKg = progressionStepKg
        self.sets = sets; self.repsTarget = repsTarget
    }
    private enum CodingKeys: String, CodingKey {
        case currentWeightKg = "current_weight_kg"
        case progressionStepKg = "progression_step_kg"
        case sets
        case repsTarget = "reps_target"
    }
}

public struct ExerciseUpdateResult: Codable, Sendable, Equatable {
    public var exerciseId: Int
    public var updated: Bool
    public init(exerciseId: Int, updated: Bool) { self.exerciseId = exerciseId; self.updated = updated }
}

/// Mirrors `mobile/src/lib/liftFormat.ts`'s `parseRepsTarget` exactly: `nil` for true-null AND for
/// any non-clean-integer text ("max", "10/side", "45s") — never a crashing force-parse.
public nonisolated func parseRepsTarget(_ raw: String?) -> Int? {
    guard let raw else { return nil }
    return Int(raw)
}

/// `PUT /api/v1/planning/plan-sessions/{id}` body / response (W-B46 Contract). Snake_case on the
/// wire for the same reason `ExerciseUpdate` is: the provider encodes outgoing bodies with a
/// plain `JSONEncoder()`.
public struct PlanSessionWeekdayUpdate: Codable, Sendable, Equatable {
    public var weekday: Int?
    public init(weekday: Int?) { self.weekday = weekday }
}

public struct PlanSessionOut: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var weekday: Int?
    public init(id: Int, name: String, weekday: Int?) { self.id = id; self.name = name; self.weekday = weekday }
}

/// Mon = 0 … Sun = 6 (Python's `date.weekday()`, which is what `plan.plan_session.weekday` holds).
/// `Calendar`'s `.weekday` component is Sun = 1 … Sat = 7, so the two need converting in one
/// documented place rather than at every call site.
public nonisolated func planWeekday(fromCalendarWeekday calendarWeekday: Int) -> Int {
    (calendarWeekday + 5) % 7
}

public nonisolated let planWeekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

public nonisolated func planWeekdayName(_ weekday: Int?) -> String? {
    guard let weekday, planWeekdayNames.indices.contains(weekday) else { return nil }
    return planWeekdayNames[weekday]
}

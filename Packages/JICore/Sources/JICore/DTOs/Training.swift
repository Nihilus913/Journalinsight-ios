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
    /// W-B81 A-5: `"apple"` (core.activity dso_key 4) or `"garmin"` — HT `_coerce_activity`. Every
    /// field below is optional: an older hub omits them and the row still decodes.
    public var source: String?
    public var avgHr: Int?
    public var maxHr: Int?
    /// Apple-only effort × minutes (HT migration 054); nil for Garmin.
    public var sessionLoad: Double?
    /// ISO-8601 UTC start ("2026-09-28T05:02:04+00:00").
    public var startTimeUtc: String?
    /// iOS 27 `HKWorkoutZoneGroup` time-in-zone, when the hub exposes it (payload `zone_time`).
    public var zoneTime: [WorkoutZoneTime]?

    public init(activityId: Int, type: String, name: String?, durationSec: Double?, distanceM: Double?,
                source: String? = nil, avgHr: Int? = nil, maxHr: Int? = nil, sessionLoad: Double? = nil,
                startTimeUtc: String? = nil, zoneTime: [WorkoutZoneTime]? = nil) {
        self.activityId = activityId; self.type = type; self.name = name
        self.durationSec = durationSec; self.distanceM = distanceM
        self.source = source; self.avgHr = avgHr; self.maxHr = maxHr; self.sessionLoad = sessionLoad
        self.startTimeUtc = startTimeUtc; self.zoneTime = zoneTime
    }

    /// W-B81: an Apple Health workout the phone uploaded (dso 4), read back from the hub.
    public var isAppleHealth: Bool { source == "apple" }

    /// `startTimeUtc` parsed; nil when absent or unparsable.
    public var startDate: Date? {
        guard let startTimeUtc else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: startTimeUtc) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: startTimeUtc)
    }
}

/// W-B81: one `HKWorkoutZoneGroup` zone — `upperBpm == nil` is the open top zone.
public struct WorkoutZoneTime: Codable, Sendable, Equatable {
    public var zone: Int
    public var lowerBpm: Int?
    public var upperBpm: Int?
    public var seconds: Double
    public init(zone: Int, lowerBpm: Int?, upperBpm: Int?, seconds: Double) {
        self.zone = zone; self.lowerBpm = lowerBpm; self.upperBpm = upperBpm; self.seconds = seconds
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
    /// W-SSOT-1 SS-2: the hub's ONE completion rule for this date (HT `app/training/completion.py`).
    /// Optional: an older hub omits it and the app's own rule answers alone.
    public var completion: HubCompletion?
    public init(date: String, activities: [DayActivity], exerciseSets: [DayExerciseSet], plannedSession: PlannedSession? = nil,
                completion: HubCompletion? = nil) {
        self.date = date; self.activities = activities; self.exerciseSets = exerciseSets
        self.plannedSession = plannedSession; self.completion = completion
    }
}

/// W-SSOT-1 SS-2: `GET /training/day/{date}` `completion` — the hub's answer to "was the planned
/// session done?" (the same rule morning_go's exercise KPI counts). Parts: `strength` / `cardio`;
/// an interval day's cardio part is filled only by a run or a ride (a walk never completes it).
/// `status` stays a string (done / partial / open) so a future value never fails the decode.
public struct HubCompletion: Codable, Sendable, Equatable {
    public struct Part: Codable, Sendable, Equatable {
        public var part: String
        public var done: Bool
        public var activityIds: [Int]
        public init(part: String, done: Bool, activityIds: [Int] = []) {
            self.part = part; self.done = done; self.activityIds = activityIds
        }
    }
    /// strength | interval | z2 | optional | rest
    public var sessionType: String
    /// false = nothing owed (rest, an optional day).
    public var owed: Bool
    public var parts: [Part]
    public var status: String
    /// The lead part is done — what the exercise KPI / streak counts.
    public var credited: Bool

    public init(sessionType: String, owed: Bool, parts: [Part], status: String, credited: Bool) {
        self.sessionType = sessionType; self.owed = owed; self.parts = parts; self.status = status; self.credited = credited
    }

    public var isDone: Bool { status == "done" }
    public var isPartial: Bool { status == "partial" }
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
    /// `plan.plan_session.session_type` — "strength" | "cardio" | "rest". Only
    /// `GET /planning/plan-sessions` (W-B40 fixer) carries it; nil everywhere else.
    public var sessionType: String?
    public init(id: Int, name: String, weekday: Int?, sessionType: String? = nil) {
        self.id = id; self.name = name; self.weekday = weekday; self.sessionType = sessionType
    }
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

// MARK: - W-B98A B98-4 (B-98 5a): one activity's km splits + HR/pace series

/// `GET /api/v1/training/activity/{id}/series` (HT `app/training/activity_series.py`): JI-computed
/// km splits and ≤ 300 HR/pace points from the stored 1 s samples (Garmin or Apple). A GPS-less,
/// speed-less Apple run → `splits == []`, every `paceSPerKm == nil`, `hrOnly == true`. 404 = unknown id.
public nonisolated struct ActivitySeries: Codable, Sendable, Equatable {
    public var activityId: Int
    public var type: String?
    public var splits: [ActivitySplit]
    public var points: [ActivitySeriesPoint]
    public var hrOnly: Bool
    /// "JI-computed, may differ from Garmin" — the hub's own words, shown under the screen.
    public var caption: String

    public init(activityId: Int, type: String?, splits: [ActivitySplit], points: [ActivitySeriesPoint], hrOnly: Bool, caption: String) {
        self.activityId = activityId; self.type = type; self.splits = splits; self.points = points
        self.hrOnly = hrOnly; self.caption = caption
    }
}

/// One km bucket (the last one may be a partial km ≥ 50 m). Missing HR / elevation = nil, never 0.
public nonisolated struct ActivitySplit: Codable, Sendable, Equatable {
    public var km: Int
    public var distanceM: Double
    public var durationS: Double
    public var paceSPerKm: Double?
    public var meanHr: Double?
    public var elevationGainM: Double?

    public init(km: Int, distanceM: Double, durationS: Double, paceSPerKm: Double?, meanHr: Double?, elevationGainM: Double?) {
        self.km = km; self.distanceM = distanceM; self.durationS = durationS
        self.paceSPerKm = paceSPerKm; self.meanHr = meanHr; self.elevationGainM = elevationGainM
    }
}

/// One chart point: `t` = seconds from the first sample; bucket-mean HR and pace (s/km).
public nonisolated struct ActivitySeriesPoint: Codable, Sendable, Equatable {
    public var t: Double
    public var hr: Double?
    public var paceSPerKm: Double?

    public init(t: Double, hr: Double?, paceSPerKm: Double?) { self.t = t; self.hr = hr; self.paceSPerKm = paceSPerKm }
}

public protocol ActivitySeriesProviding: Sendable {
    /// `GET /api/v1/training/activity/{id}/series`.
    func activitySeries(activityId: Int) async throws -> ActivitySeries
}

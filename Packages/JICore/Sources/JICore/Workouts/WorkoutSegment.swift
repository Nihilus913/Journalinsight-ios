import Foundation

/// W-B40 L2 (B-40b-1) — spec §2.1 `segments`: ordered `[{sport, steps}]`. A cardio segment holds
/// cardio steps only; a strength segment holds strength steps and may carry cardio steps with
/// `purpose ∈ warmup|cooldown` (live: the jump-rope warm-up). The hub (Pydantic, §3) is the
/// validator of record; nothing here rewrites a row it received.
public enum WorkoutSport: String, Codable, Sendable, CaseIterable {
    case running, walking, cycling, strength

    /// WorkoutKit can run it (spec §4: strength has no WorkoutKit type — skipped, B-38 logs it).
    public var isCardio: Bool { self != .strength }
}

public struct WorkoutSegment: Codable, Sendable, Equatable {
    public var sport: WorkoutSport
    public var steps: [SegmentStep]
    public init(sport: WorkoutSport, steps: [SegmentStep]) { self.sport = sport; self.steps = steps }
}

/// `Step = .cardio(CardioStep) | .strength(StrengthStep)`. On the wire the two are told apart by
/// shape: a strength step carries `exercise_key`, a cardio step carries `purpose`.
public enum SegmentStep: Codable, Sendable, Equatable {
    case cardio(CardioStep)
    case strength(StrengthStep)

    public var cardio: CardioStep? { if case .cardio(let s) = self { s } else { nil } }
    public var strength: StrengthStep? { if case .strength(let s) = self { s } else { nil } }

    private enum Probe: String, CodingKey { case exerciseKey }

    public init(from decoder: any Decoder) throws {
        let probe = try decoder.container(keyedBy: Probe.self)
        self = probe.contains(.exerciseKey) ? .strength(try StrengthStep(from: decoder)) : .cardio(try CardioStep(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .cardio(let s): try s.encode(to: encoder)
        case .strength(let s): try s.encode(to: encoder)
        }
    }
}

/// Cardio step `{purpose, end, target, repeat, description?}` (spec §2.1).
public struct CardioStep: Codable, Sendable, Equatable {
    public var purpose: WorkoutStepPurpose
    public var end: StepEnd
    public var target: StepTarget
    public var `repeat`: Int
    public var description: String?

    public init(purpose: WorkoutStepPurpose, end: StepEnd, target: StepTarget, repeat n: Int = 1, description: String? = nil) {
        self.purpose = purpose; self.end = end; self.target = target; self.repeat = n; self.description = description
    }

    /// A B-37 compat step: time end, absolute-bpm range.
    public init(_ legacy: WorkoutStep) {
        self.init(purpose: legacy.purpose, end: .time(seconds: legacy.seconds),
                  target: .hrRange(lo: legacy.hrLo, hi: legacy.hrHi), repeat: legacy.repeat)
    }
}

/// `end = {type: time, seconds>0} | {type: distance, meters>0} | {type: lap}` — lap = "until I
/// press lap".
public enum StepEnd: Codable, Sendable, Equatable {
    case time(seconds: Int)
    case distance(meters: Double)
    case lap

    private enum Keys: String, CodingKey { case type, seconds, meters }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "time": self = .time(seconds: try c.decode(Int.self, forKey: .seconds))
        case "distance": self = .distance(meters: try c.decode(Double.self, forKey: .meters))
        case "lap": self = .lap
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown step end type \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .time(let s): try c.encode("time", forKey: .type); try c.encode(s, forKey: .seconds)
        case .distance(let m): try c.encode("distance", forKey: .type); try c.encode(m, forKey: .meters)
        case .lap: try c.encode("lap", forKey: .type)
        }
    }
}

/// `target = {type: none} | {type: hr_range, lo, hi} | {type: hr_zone, zone 1–5}`. A zone is
/// resolved to bpm from the USER's zones at send time (B-57 W4), never from app constants.
public enum StepTarget: Codable, Sendable, Equatable {
    case none
    case hrRange(lo: Int, hi: Int)
    case hrZone(Int)

    private enum Keys: String, CodingKey { case type, lo, hi, zone }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "none": self = .none
        case "hr_range": self = .hrRange(lo: try c.decode(Int.self, forKey: .lo), hi: try c.decode(Int.self, forKey: .hi))
        case "hr_zone": self = .hrZone(try c.decode(Int.self, forKey: .zone))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown step target type \(other)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .none: try c.encode("none", forKey: .type)
        case .hrRange(let lo, let hi): try c.encode("hr_range", forKey: .type); try c.encode(lo, forKey: .lo); try c.encode(hi, forKey: .hi)
        case .hrZone(let z): try c.encode("hr_zone", forKey: .type); try c.encode(z, forKey: .zone)
        }
    }
}

/// Strength step `{exercise_key, garmin_category, garmin_exercise?, sets≥1, reps≥1 | seconds>0,
/// weight_kg?, rest_seconds?, description?}` (spec §2.1). `exerciseKey` is the app's exercise
/// identity (spec §10.1 — what B-38 logs sets against).
public struct StrengthStep: Codable, Sendable, Equatable {
    public var exerciseKey: String
    public var garminCategory: String
    public var garminExercise: String?
    public var sets: Int
    public var reps: Int?
    public var seconds: Int?
    public var weightKg: Double?
    public var restSeconds: Int?
    public var description: String?

    public init(exerciseKey: String, garminCategory: String, garminExercise: String? = nil, sets: Int,
                reps: Int? = nil, seconds: Int? = nil, weightKg: Double? = nil, restSeconds: Int? = nil, description: String? = nil) {
        self.exerciseKey = exerciseKey; self.garminCategory = garminCategory; self.garminExercise = garminExercise
        self.sets = sets; self.reps = reps; self.seconds = seconds; self.weightKg = weightKg
        self.restSeconds = restSeconds; self.description = description
    }
}

import Foundation

/// W-B38-A A-8 — the hub's strength-log routes (`app/planning/strength_log.py`, mounted under
/// `/api/v1/planning/strength-sessions`, card rows A-2..A-4). Request bodies carry explicit
/// snake_case keys (`HubClient.send` encodes with a plain `JSONEncoder()`); the same bodies are
/// the `strength` outbox payloads (plain encoder/decoder there too, so the keys round-trip).
/// Responses decode with `JSON.decoder` (`.convertFromSnakeCase`) and are deliberately lenient:
/// every write answer is an ack whose fields are all optional.

/// `POST /strength-sessions`.
public struct StrengthSessionCreate: Codable, Sendable, Equatable {
    public var clientId: String
    public var date: String
    public var startedAt: String
    /// `plan.plan_session.session_id` this session logs; nil = a free session.
    public var sessionId: Int?

    public init(clientId: String, date: String, startedAt: String, sessionId: Int?) {
        self.clientId = clientId; self.date = date; self.startedAt = startedAt; self.sessionId = sessionId
    }

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id", date, startedAt = "started_at", sessionId = "session_id"
    }
}

/// `POST /strength-sessions/{id}/sets` and `PUT /strength-sessions/{id}/sets/{client_id}`.
public struct StrengthSetIn: Codable, Sendable, Equatable {
    public var clientId: String
    public var exerciseKey: String
    public var exerciseId: Int?
    public var setIndex: Int
    /// "reps" | "timed".
    public var kind: String
    public var reps: Int?
    public var weightKg: Double?
    public var durationS: Int?
    public var rpe: Double?
    public var performedAt: String

    public init(clientId: String, exerciseKey: String, exerciseId: Int?, setIndex: Int, kind: String,
                reps: Int?, weightKg: Double?, durationS: Int?, rpe: Double?, performedAt: String) {
        self.clientId = clientId; self.exerciseKey = exerciseKey; self.exerciseId = exerciseId
        self.setIndex = setIndex; self.kind = kind; self.reps = reps; self.weightKg = weightKg
        self.durationS = durationS; self.rpe = rpe; self.performedAt = performedAt
    }

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id", exerciseKey = "exercise_key", exerciseId = "exercise_id", setIndex = "set_index"
        case kind, reps, weightKg = "weight_kg", durationS = "duration_s", rpe, performedAt = "performed_at"
    }
}

/// One explicit progression move the app computed (`JICompute.Progression`); the hub writes
/// exactly these into `plan.session_exercises` and nothing else (A-3). Toggle off → `[]`.
public struct StrengthAdvance: Codable, Sendable, Equatable {
    public var exerciseId: Int
    public var currentWeightKg: Double
    public init(exerciseId: Int, currentWeightKg: Double) { self.exerciseId = exerciseId; self.currentWeightKg = currentWeightKg }
    enum CodingKeys: String, CodingKey { case exerciseId = "exercise_id", currentWeightKg = "current_weight_kg" }
}

/// `POST /strength-sessions/{id}/complete`.
public struct StrengthSessionComplete: Codable, Sendable, Equatable {
    public var endedAt: String
    public var advance: [StrengthAdvance]
    public init(endedAt: String, advance: [StrengthAdvance]) { self.endedAt = endedAt; self.advance = advance }
    enum CodingKeys: String, CodingKey { case endedAt = "ended_at", advance }
}

/// A hub-side set (history, last-sets). Snake-case wire keys arrive camelCased by `JSON.decoder`.
public struct StrengthSetOut: Codable, Sendable, Equatable {
    public var setLogId: Int?
    public var clientId: String?
    public var sessionLogId: Int?
    public var exerciseKey: String
    public var exerciseId: Int?
    public var setIndex: Int?
    public var kind: String?
    public var reps: Int?
    public var weightKg: Double?
    public var durationS: Int?
    public var rpe: Double?
    public var performedAt: String?

    public init(setLogId: Int? = nil, clientId: String?, sessionLogId: Int? = nil, exerciseKey: String, exerciseId: Int? = nil,
                setIndex: Int?, kind: String? = "reps", reps: Int?, weightKg: Double?, durationS: Int? = nil,
                rpe: Double? = nil, performedAt: String?) {
        self.setLogId = setLogId; self.clientId = clientId; self.sessionLogId = sessionLogId; self.exerciseKey = exerciseKey
        self.exerciseId = exerciseId; self.setIndex = setIndex; self.kind = kind; self.reps = reps; self.weightKg = weightKg
        self.durationS = durationS; self.rpe = rpe; self.performedAt = performedAt
    }
}

/// A hub-side session (history list and the create/complete answers).
public struct StrengthSessionOut: Codable, Sendable, Equatable {
    public var sessionLogId: Int?
    public var clientId: String?
    public var sessionId: Int?
    public var date: String?
    public var startedAt: String?
    public var endedAt: String?
    public var sets: [StrengthSetOut]?

    public init(sessionLogId: Int?, clientId: String?, sessionId: Int? = nil, date: String?, startedAt: String?,
                endedAt: String? = nil, sets: [StrengthSetOut]? = nil) {
        self.sessionLogId = sessionLogId; self.clientId = clientId; self.sessionId = sessionId; self.date = date
        self.startedAt = startedAt; self.endedAt = endedAt; self.sets = sets
    }
}

/// The answer of a set write (`POST …/sets`, `PUT …/sets/{client_id}`) — an ack, all optional.
public struct StrengthWriteAck: Codable, Sendable, Equatable {
    public var setLogId: Int?
    public var sessionLogId: Int?
    public var clientId: String?
    public init(setLogId: Int? = nil, sessionLogId: Int? = nil, clientId: String? = nil) {
        self.setLogId = setLogId; self.sessionLogId = sessionLogId; self.clientId = clientId
    }
}

/// `GET /strength-sessions` answers either a bare array or `{"sessions": [...]}`; `GET …/last-sets`
/// either a bare array or `{"sets": [...]}`. Both shapes decode.
public struct StrengthSessionList: Decodable, Sendable, Equatable {
    public var sessions: [StrengthSessionOut]
    public init(sessions: [StrengthSessionOut]) { self.sessions = sessions }
    enum Keys: String, CodingKey { case sessions }
    public init(from decoder: Decoder) throws {
        if let arr = try? [StrengthSessionOut](from: decoder) { sessions = arr; return }
        sessions = try decoder.container(keyedBy: Keys.self).decode([StrengthSessionOut].self, forKey: .sessions)
    }
}

public struct StrengthSetList: Decodable, Sendable, Equatable {
    public var sets: [StrengthSetOut]
    public init(sets: [StrengthSetOut]) { self.sets = sets }
    enum Keys: String, CodingKey { case sets }
    public init(from decoder: Decoder) throws {
        if let arr = try? [StrengthSetOut](from: decoder) { sets = arr; return }
        sets = try decoder.container(keyedBy: Keys.self).decode([StrengthSetOut].self, forKey: .sets)
    }
}

/// The provider (fixtures, `MockDataProvider`, an older hub) has no strength-log routes.
public struct StrengthLogUnavailable: Error, Sendable, Equatable {
    public init() {}
}

/// X-1 (A-6, XC half): an advance with a missing / non-positive weight is never sent.
public struct StrengthAdvanceWouldClear: Error, Sendable, Equatable {
    public let exerciseId: Int
    public init(exerciseId: Int) { self.exerciseId = exerciseId }
}

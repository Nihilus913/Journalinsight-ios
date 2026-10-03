import Foundation
import GRDB

/// W-B38-A A-7 — one logged strength session on this phone (`strength_session_log`,
/// `v5_strength_log`). `clientId` is the UUID the hub dedupes on (`plan.strength_session.client_id`);
/// `remoteId` is the hub's `session_log_id`, nil until the outbox's create drains.
public struct StrengthSessionLog: Sendable, Equatable, Identifiable, Codable {
    public var clientId: String
    public var remoteId: Int?
    /// `plan.plan_session` id of the training this session logs (nil = free session).
    public var sessionId: Int?
    public var sessionName: String?
    public var date: String
    public var startedAt: String
    public var endedAt: String?
    public var id: String { clientId }
    public var isComplete: Bool { endedAt != nil }

    public init(clientId: String = UUID().uuidString.lowercased(), remoteId: Int? = nil, sessionId: Int? = nil,
                sessionName: String? = nil, date: String, startedAt: String, endedAt: String? = nil) {
        self.clientId = clientId; self.remoteId = remoteId; self.sessionId = sessionId
        self.sessionName = sessionName; self.date = date; self.startedAt = startedAt; self.endedAt = endedAt
    }
}

/// One logged set (`strength_set_log`). `kind == .timed` sets carry `durationS`, rep sets `reps`.
public struct StrengthSetLog: Sendable, Equatable, Identifiable, Codable {
    public enum Kind: String, Sendable, Codable { case reps, timed }

    public var clientId: String
    public var sessionClientId: String
    /// The catalogue key (`WorkoutExerciseCatalogue` / `session_exercises.exercise_name`).
    public var exerciseKey: String
    public var exerciseId: Int?
    public var setIndex: Int
    public var kind: Kind
    public var reps: Int?
    public var weightKg: Double?
    public var durationS: Int?
    public var rpe: Double?
    public var performedAt: String
    public var id: String { clientId }

    public init(clientId: String = UUID().uuidString.lowercased(), sessionClientId: String, exerciseKey: String,
                exerciseId: Int? = nil, setIndex: Int, kind: Kind = .reps, reps: Int? = nil, weightKg: Double? = nil,
                durationS: Int? = nil, rpe: Double? = nil, performedAt: String) {
        self.clientId = clientId; self.sessionClientId = sessionClientId; self.exerciseKey = exerciseKey
        self.exerciseId = exerciseId; self.setIndex = setIndex; self.kind = kind; self.reps = reps
        self.weightKg = weightKg; self.durationS = durationS; self.rpe = rpe; self.performedAt = performedAt
    }
}

/// W-B38-A A-7 — the local-first strength log. Every write lands HERE first (the screen then
/// enqueues the matching `strength` outbox row); every read is a plain SQLite read — this store has
/// no hub dependency at all, so History and the logger render offline. Hub history merged in by
/// `mergeFromHub` upserts on the client UUIDs, so a row the phone itself sent never doubles.
public struct StrengthSessionLogStore: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    // MARK: sessions

    /// Idempotent on `clientId` (a second start of the same session is a no-op).
    public func startSession(_ s: StrengthSessionLog) throws {
        try db.pool.write { db in try Self.insertSession(db, s, replace: false) }
    }

    public func session(clientId: String) throws -> StrengthSessionLog? {
        try db.pool.read { db in
            try Self.sessions(db, "WHERE client_id = ?", [clientId]).first
        }
    }

    /// The not-yet-completed session of `date` (newest), the one the logger resumes.
    public func openSession(date: String) throws -> StrengthSessionLog? {
        try db.pool.read { db in
            try Self.sessions(db, "WHERE date = ? AND ended_at IS NULL ORDER BY started_at DESC, id DESC", [date]).first
        }
    }

    /// Sessions with `from <= date <= to`, newest first.
    public func sessions(from: String, to: String) throws -> [StrengthSessionLog] {
        try db.pool.read { db in
            try Self.sessions(db, "WHERE date >= ? AND date <= ? ORDER BY date DESC, started_at DESC, id DESC", [from, to])
        }
    }

    public func complete(sessionClientId: String, endedAt: String) throws {
        try db.pool.write { db in
            try db.execute(sql: "UPDATE strength_session_log SET ended_at = ? WHERE client_id = ?", arguments: [endedAt, sessionClientId])
        }
    }

    /// The hub's `session_log_id`, once the create drained.
    public func setRemoteId(sessionClientId: String, remoteId: Int) throws {
        try db.pool.write { db in
            try db.execute(sql: "UPDATE strength_session_log SET remote_id = ? WHERE client_id = ?", arguments: [remoteId, sessionClientId])
        }
    }

    // MARK: sets

    /// Insert, or edit in place when `clientId` already exists (gap #31).
    public func upsertSet(_ s: StrengthSetLog) throws {
        try db.pool.write { db in try Self.upsertSet(db, s) }
    }

    public func deleteSet(clientId: String) throws {
        try db.pool.write { db in try db.execute(sql: "DELETE FROM strength_set_log WHERE client_id = ?", arguments: [clientId]) }
    }

    /// A session's sets in the order they were done.
    public func sets(sessionClientId: String) throws -> [StrengthSetLog] {
        try db.pool.read { db in
            try Self.sets(db, "WHERE session_client_id = ? ORDER BY performed_at ASC, set_index ASC, id ASC", [sessionClientId])
        }
    }

    /// The most recent completed-or-open session's sets of `exerciseKey` before `date` (exclusive)
    /// — the local half of gap #29's "last time" defaults.
    public func lastSets(exerciseKey: String, before date: String) throws -> [StrengthSetLog] {
        try db.pool.read { db in
            guard let session = try String.fetchOne(db, sql: """
                SELECT s.client_id FROM strength_session_log s
                JOIN strength_set_log x ON x.session_client_id = s.client_id
                WHERE x.exercise_key = ? AND s.date < ?
                ORDER BY s.date DESC, s.started_at DESC LIMIT 1
                """, arguments: [exerciseKey, date]) else { return [] }
            return try Self.sets(db, "WHERE session_client_id = ? AND exercise_key = ? ORDER BY set_index ASC, performed_at ASC", [session, exerciseKey])
        }
    }

    /// Hub history (A-11) merged into the cache: sessions and sets upserted on their client ids.
    /// Never deletes a local row (an unsent local set is not on the hub yet).
    public func mergeFromHub(_ sessions: [(session: StrengthSessionLog, sets: [StrengthSetLog])]) throws {
        try db.pool.write { db in
            for entry in sessions {
                try Self.insertSession(db, entry.session, replace: true)
                for s in entry.sets { try Self.upsertSet(db, s) }
            }
        }
    }

    // MARK: SQL

    private static func insertSession(_ db: Database, _ s: StrengthSessionLog, replace: Bool) throws {
        let conflict = replace
            ? """
              ON CONFLICT(client_id) DO UPDATE SET
                remote_id = COALESCE(excluded.remote_id, remote_id),
                session_id = COALESCE(excluded.session_id, session_id),
                session_name = COALESCE(excluded.session_name, session_name),
                date = excluded.date, started_at = excluded.started_at,
                ended_at = COALESCE(excluded.ended_at, ended_at)
              """
            : "ON CONFLICT(client_id) DO NOTHING"
        try db.execute(sql: """
            INSERT INTO strength_session_log (client_id, remote_id, session_id, session_name, date, started_at, ended_at)
            VALUES (?, ?, ?, ?, ?, ?, ?) \(conflict)
            """, arguments: [s.clientId, s.remoteId, s.sessionId, s.sessionName, s.date, s.startedAt, s.endedAt])
    }

    private static func upsertSet(_ db: Database, _ s: StrengthSetLog) throws {
        try db.execute(sql: """
            INSERT INTO strength_set_log
              (client_id, session_client_id, exercise_key, exercise_id, set_index, kind, reps, weight_kg, duration_s, rpe, performed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(client_id) DO UPDATE SET
              exercise_key = excluded.exercise_key, exercise_id = excluded.exercise_id,
              set_index = excluded.set_index, kind = excluded.kind, reps = excluded.reps,
              weight_kg = excluded.weight_kg, duration_s = excluded.duration_s, rpe = excluded.rpe,
              performed_at = excluded.performed_at
            """, arguments: [s.clientId, s.sessionClientId, s.exerciseKey, s.exerciseId, s.setIndex, s.kind.rawValue,
                             s.reps, s.weightKg, s.durationS, s.rpe, s.performedAt])
    }

    private static func sessions(_ db: Database, _ clause: String, _ args: StatementArguments) throws -> [StrengthSessionLog] {
        try Row.fetchAll(db, sql: """
            SELECT client_id, remote_id, session_id, session_name, date, started_at, ended_at
            FROM strength_session_log \(clause)
            """, arguments: args).map { r in
            StrengthSessionLog(clientId: r["client_id"], remoteId: r["remote_id"], sessionId: r["session_id"],
                               sessionName: r["session_name"], date: r["date"], startedAt: r["started_at"], endedAt: r["ended_at"])
        }
    }

    private static func sets(_ db: Database, _ clause: String, _ args: StatementArguments) throws -> [StrengthSetLog] {
        try Row.fetchAll(db, sql: """
            SELECT client_id, session_client_id, exercise_key, exercise_id, set_index, kind, reps, weight_kg, duration_s, rpe, performed_at
            FROM strength_set_log \(clause)
            """, arguments: args).map { r in
            StrengthSetLog(clientId: r["client_id"], sessionClientId: r["session_client_id"], exerciseKey: r["exercise_key"],
                           exerciseId: r["exercise_id"], setIndex: r["set_index"],
                           kind: StrengthSetLog.Kind(rawValue: r["kind"]) ?? .reps, reps: r["reps"], weightKg: r["weight_kg"],
                           durationS: r["duration_s"], rpe: r["rpe"], performedAt: r["performed_at"])
        }
    }
}

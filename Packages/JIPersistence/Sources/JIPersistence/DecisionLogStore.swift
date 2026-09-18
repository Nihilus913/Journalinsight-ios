import Foundation
import GRDB
import JICore

/// Oracle: `mobile/src/decisions/DecisionLogStore.ts`. Local-first store over
/// `decision_log_mirror` (created by `Migrations.swift`'s `v4_decision_log`), the device's own
/// record of every gate answer.
///
/// IMPORTANT DIFFERENCE from `GoalStore`'s `goal_targets_mirror` (and the KPI-target / challenge
/// mirrors): those mirror a hub GET this device can re-fetch and diff against. `plan.decision_log`
/// has no such GET — grepping HT's `app/planning/router.py` finds only `POST /gate/respond`
/// writing a row, nothing reading the list back. So this store is not a refresh-mirror: rows are
/// written LOCALLY FIRST (`append`, `remoteLogId` nil, `synced` false) the moment the user answers,
/// and `markSynced` attaches the hub's returned `log_id` once the POST actually succeeds. A row
/// that never gets marked (hub unreachable at POST time) stays visible via `pendingSync()` for a
/// later retry — nothing is silently dropped.
///
/// Append-only: an existing row is never updated except to attach the remote id.

/// `mobile/src/decisions/DecisionLogStore.ts::DecisionLogEntry`.
public struct DecisionLogEntry: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var remoteLogId: Int?
    public var loggedAt: String
    public var windowDays: Int
    public var recommendation: String
    public var userChoice: String
    public var overrideReason: String?
    public var synced: Bool

    public init(
        id: Int64, remoteLogId: Int?, loggedAt: String, windowDays: Int,
        recommendation: String, userChoice: String, overrideReason: String?, synced: Bool
    ) {
        self.id = id; self.remoteLogId = remoteLogId; self.loggedAt = loggedAt
        self.windowDays = windowDays; self.recommendation = recommendation
        self.userChoice = userChoice; self.overrideReason = overrideReason; self.synced = synced
    }
}

/// `NewDecisionLogEntry` — the oracle's `Omit<DecisionLogEntry, "id" | "remoteLogId" | "synced">`:
/// the three fields the store itself assigns are not the caller's to supply.
public struct NewDecisionLogEntry: Sendable, Equatable {
    public var loggedAt: String
    public var windowDays: Int
    public var recommendation: String
    public var userChoice: String
    public var overrideReason: String?

    public init(loggedAt: String, windowDays: Int, recommendation: String, userChoice: String, overrideReason: String? = nil) {
        self.loggedAt = loggedAt; self.windowDays = windowDays
        self.recommendation = recommendation; self.userChoice = userChoice
        self.overrideReason = overrideReason
    }
}

public struct DecisionLogStore: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    /// Records a decision the moment it is made, before the hub POST even resolves. Returns the
    /// local row id (pass it to `markSynced` later). Oracle: `appendDecision`.
    @discardableResult
    public func append(_ entry: NewDecisionLogEntry) throws -> Int64 {
        try db.pool.write { db in
            try db.execute(
                sql: """
                INSERT INTO decision_log_mirror
                  (remote_log_id, logged_at, window_days, recommendation, user_choice, override_reason, synced)
                VALUES (NULL, ?, ?, ?, ?, ?, 0)
                """,
                arguments: [entry.loggedAt, entry.windowDays, entry.recommendation, entry.userChoice, entry.overrideReason]
            )
            return db.lastInsertedRowID
        }
    }

    /// Attaches the hub's `POST /gate/respond` `log_id` once the write actually succeeds, and
    /// flips `synced`. Oracle: `markSynced`.
    public func markSynced(localId: Int64, remoteLogId: Int?) throws {
        try db.pool.write { db in
            try db.execute(
                sql: "UPDATE decision_log_mirror SET remote_log_id = ?, synced = 1 WHERE id = ?",
                arguments: [remoteLogId, localId]
            )
        }
    }

    /// Newest-first, capped at `limit`. Oracle: `recentDecisions`.
    public func recent(limit: Int) throws -> [DecisionLogEntry] {
        try db.pool.read { db in
            try Self.rows(db, sql: "\(Self.selectColumns) ORDER BY id DESC LIMIT ?", arguments: [limit])
        }
    }

    /// Every decision ever recorded, newest first — for full-history export, unlike `recent`'s
    /// bounded window. Oracle: `listAll`.
    public func listAll() throws -> [DecisionLogEntry] {
        try db.pool.read { db in
            try Self.rows(db, sql: "\(Self.selectColumns) ORDER BY id DESC", arguments: [])
        }
    }

    /// Rows still waiting on a hub POST to confirm (`synced = 0`) — oldest first, the order a
    /// retry loop should walk them in. Oracle: `pendingSync`.
    public func pendingSync() throws -> [DecisionLogEntry] {
        try db.pool.read { db in
            try Self.rows(db, sql: "\(Self.selectColumns) WHERE synced = 0 ORDER BY id ASC", arguments: [])
        }
    }

    private static let selectColumns = """
        SELECT id, remote_log_id, logged_at, window_days, recommendation, user_choice, override_reason, synced
        FROM decision_log_mirror
        """

    private static func rows(_ db: Database, sql: String, arguments: StatementArguments) throws -> [DecisionLogEntry] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            DecisionLogEntry(
                id: row["id"],
                remoteLogId: row["remote_log_id"],
                loggedAt: row["logged_at"],
                windowDays: row["window_days"],
                recommendation: row["recommendation"],
                userChoice: row["user_choice"],
                overrideReason: row["override_reason"],
                synced: (row["synced"] as Int) != 0
            )
        }
    }
}

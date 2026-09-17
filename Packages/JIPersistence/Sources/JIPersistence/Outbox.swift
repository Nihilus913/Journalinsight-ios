import Foundation
import GRDB

/// One durable-write-queue row (`outbox` table, migration `v2_outbox`). `payload` is the raw JSON
/// body a later drainer needs to replay the write (e.g. a `WeighinBody`) — this store is
/// deliberately kind-agnostic (`kind` is a caller-chosen tag like `"weighin"`) so it can back more
/// than one offline write in a later wave without a schema change.
public struct OutboxRow: Sendable, Equatable {
    public var id: Int64
    public var kind: String
    public var payload: Data
    public var createdAt: String
    public var attempts: Int
    public var lastError: String?
}

/// A durable write queue: the entering-a-weight flow (`WeighInViewModel`, JIFeatures) enqueues a
/// row here BEFORE any network call, so the write survives the app being offline or the process
/// being killed mid-request. A drainer (`OutboxDrainer`, JIFeatures) later calls `pending()` and,
/// per row, either `markSent` (delivered — retired by deletion, there is nothing left to retry) or
/// `markFailed` (bumps `attempts` and records the hub's own error text for the next attempt).
public struct Outbox: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    @discardableResult
    public func enqueue<T: Encodable>(kind: String, payload: T, now: Date = Date()) throws -> Int64 {
        // Plain `JSONEncoder()`, deliberately NOT `JSON.encoder`: this is the outbox's own storage
        // format, not a hub wire body, and a payload type (e.g. `WeighinBody`) may already carry
        // explicit snake_case `CodingKeys` for the hub — layering `.convertToSnakeCase` on top of
        // an already-snake_case key mangles it (same trap `HubClient.send`'s doc comment calls
        // out). A drainer must decode with a matching plain `JSONDecoder()`.
        let blob = try JSONEncoder().encode(payload)
        let createdAt = now.ISO8601Format()
        return try db.pool.write { db in
            try db.execute(
                sql: "INSERT INTO outbox(kind, payload, created_at, attempts, last_error) VALUES (?, ?, ?, 0, NULL)",
                arguments: [kind, blob, createdAt]
            )
            return db.lastInsertedRowID
        }
    }

    /// Every row not yet delivered, oldest first. A sent row is deleted (see `markSent`), so this
    /// is a single unconditional SELECT rather than a status filter.
    public func pending() throws -> [OutboxRow] {
        try db.pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, kind, payload, created_at, attempts, last_error FROM outbox ORDER BY id ASC").map { row in
                OutboxRow(
                    id: row["id"], kind: row["kind"], payload: row["payload"],
                    createdAt: row["created_at"], attempts: row["attempts"], lastError: row["last_error"]
                )
            }
        }
    }

    /// The row was delivered — retired by deletion (nothing left to retry).
    public func markSent(id: Int64) throws {
        try db.pool.write { db in try db.execute(sql: "DELETE FROM outbox WHERE id = ?", arguments: [id]) }
    }

    /// The row failed this attempt (offline, or the hub rejected it) — stays pending, with
    /// `attempts` bumped and `lastError` set to the caller's description of what went wrong (e.g.
    /// a 502's `detail`, verbatim) for the next drain pass / for display.
    public func markFailed(id: Int64, error: String) throws {
        try db.pool.write { db in
            try db.execute(sql: "UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?", arguments: [error, id])
        }
    }
}

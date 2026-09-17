import Foundation
import GRDB
import JIVault

/// One journal entry (oracle: `Entry` in `mobile/src/journal/types.ts`). `tags` is a denormalized
/// read-side convenience — the `entries` table itself never stores them (see `entry_tags`).
public struct Entry: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var date: String
    public var ts: String
    public var text: String
    public var durationSec: Int
    public var mood: String?
    public var tags: [String]
    public init(id: Int64, date: String, ts: String, text: String, durationSec: Int, mood: String?, tags: [String]) {
        self.id = id; self.date = date; self.ts = ts; self.text = text
        self.durationSec = durationSec; self.mood = mood; self.tags = tags
    }
}

/// A write to `entries` (oracle: `NewEntry`). `date`/`durationSec`/`mood`/`tags` mirror the RN
/// shape verbatim; `text` is required (RN's form never submits an empty entry).
public struct NewEntry: Sendable, Equatable {
    public var date: String
    public var text: String
    public var durationSec: Int
    public var mood: String?
    public var tags: [String]
    public init(date: String, text: String, durationSec: Int, mood: String?, tags: [String]) {
        self.date = date; self.text = text; self.durationSec = durationSec
        self.mood = mood; self.tags = tags
    }
}

/// CRUD over the `entries`/`tags`/`entry_tags` tables from migration `v3_capture` (oracle:
/// `JournalStore` in `mobile/src/journal/JournalStore.ts`). `cipher` (E13-7 parity) seals/opens
/// `text`/`mood` at the write/read boundary only — every SQL statement, column, and returned shape
/// is unchanged, so this is invisible to callers. Defaults to `IdentityCipher()`, exactly like RN's
/// `NOOP_CIPHER` default — only the production caller (`JournalViewModel`) passes a real
/// `VaultManager`-issued cipher.
public struct JournalStore: Sendable {
    private let db: AppDatabase
    private let cipher: any FieldCipher

    public init(db: AppDatabase, cipher: any FieldCipher = IdentityCipher()) {
        self.db = db
        self.cipher = cipher
    }

    @discardableResult
    public func addEntry(_ n: NewEntry, now: Date = Date()) throws -> Int64 {
        let nowISO = now.ISO8601Format()
        let text = try cipher.seal(n.text)
        let mood = try n.mood.map { try cipher.seal($0) }
        let id: Int64 = try db.pool.write { grdb in
            try grdb.execute(
                sql: """
                    INSERT INTO entries (date, ts, text, duration_sec, mood, created_at, updated_at, synced)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                    """,
                arguments: [n.date, nowISO, text, n.durationSec, mood, nowISO, nowISO]
            )
            return grdb.lastInsertedRowID
        }
        try setTags(entryId: id, tags: n.tags)
        return id
    }

    public func updateEntry(id: Int64, _ n: NewEntry, now: Date = Date()) throws {
        let nowISO = now.ISO8601Format()
        let text = try cipher.seal(n.text)
        let mood = try n.mood.map { try cipher.seal($0) }
        try db.pool.write { grdb in
            try grdb.execute(
                sql: "UPDATE entries SET date = ?, text = ?, duration_sec = ?, mood = ?, updated_at = ? WHERE id = ?",
                arguments: [n.date, text, n.durationSec, mood, nowISO, id]
            )
            try grdb.execute(sql: "DELETE FROM entry_tags WHERE entry_id = ?", arguments: [id])
        }
        try setTags(entryId: id, tags: n.tags)
    }

    public func deleteEntry(id: Int64) throws {
        try db.pool.write { grdb in
            try grdb.execute(sql: "DELETE FROM entry_tags WHERE entry_id = ?", arguments: [id])
            try grdb.execute(sql: "DELETE FROM entries WHERE id = ?", arguments: [id])
        }
    }

    /// Newest first (`ts DESC, id DESC`), matching RN's `listEntries`.
    public func listEntries() throws -> [Entry] {
        try db.pool.read { grdb in
            let rows = try Row.fetchAll(
                grdb, sql: "SELECT id, date, ts, text, duration_sec, mood FROM entries ORDER BY ts DESC, id DESC"
            )
            let tagRows = try Row.fetchAll(
                grdb,
                sql: """
                    SELECT entry_tags.entry_id AS entry_id, tags.name AS name
                    FROM entry_tags JOIN tags ON tags.id = entry_tags.tag_id
                    """
            )
            var tagsByEntry: [Int64: [String]] = [:]
            for row in tagRows {
                let entryId: Int64 = row["entry_id"]
                tagsByEntry[entryId, default: []].append(row["name"])
            }
            return try rows.map { row in
                let id: Int64 = row["id"]
                let rawText: String = row["text"]
                let rawMood: String? = row["mood"]
                return Entry(
                    id: id,
                    date: row["date"],
                    ts: row["ts"],
                    text: try cipher.open(rawText),
                    durationSec: row["duration_sec"],
                    mood: try rawMood.map { try cipher.open($0) },
                    tags: tagsByEntry[id] ?? []
                )
            }
        }
    }

    /// Distinct entry dates, newest first — feeds streak/calendar computations.
    public func allDates() throws -> [String] {
        try db.pool.read { grdb in
            try String.fetchAll(grdb, sql: "SELECT DISTINCT date FROM entries ORDER BY date DESC")
        }
    }

    public func allTags() throws -> [String] {
        try db.pool.read { grdb in
            try String.fetchAll(grdb, sql: "SELECT name FROM tags ORDER BY name ASC")
        }
    }

    /// Reads the raw (still-sealed, if a real cipher is in play) `text`/`mood` columns for a given
    /// entry id — a test-only seam so `JournalStoreTests` can assert the on-disk value is actually
    /// ciphertext, never plaintext, without reaching into GRDB directly.
    public func rawColumns(id: Int64) throws -> (text: String, mood: String?)? {
        try db.pool.read { grdb in
            guard let row = try Row.fetchOne(grdb, sql: "SELECT text, mood FROM entries WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return (row["text"], row["mood"])
        }
    }

    private func setTags(entryId: Int64, tags: [String]) throws {
        guard !tags.isEmpty else { return }
        try db.pool.write { grdb in
            for name in tags {
                try grdb.execute(sql: "INSERT OR IGNORE INTO tags (name) VALUES (?)", arguments: [name])
                guard let tagId = try Int64.fetchOne(grdb, sql: "SELECT id FROM tags WHERE name = ?", arguments: [name]) else { continue }
                try grdb.execute(
                    sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_id) VALUES (?, ?)",
                    arguments: [entryId, tagId]
                )
            }
        }
    }
}

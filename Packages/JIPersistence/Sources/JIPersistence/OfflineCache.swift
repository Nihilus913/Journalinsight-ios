import Foundation
import GRDB
import JICore

public struct CacheHit<T: Sendable>: Sendable { public let value: T; public let fetchedAt: Date }

public struct OfflineCache: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func put<T: Encodable>(_ key: String, _ value: T) throws {
        let blob = try JSON.encoder.encode(value)
        let now = Date().ISO8601Format()
        try db.pool.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO cache(key, json, fetched_at) VALUES (?, ?, ?)", arguments: [key, blob, now])
        }
    }

    public func get<T: Decodable & Sendable>(_ key: String, as: T.Type) throws -> CacheHit<T>? {
        let row: Row? = try db.pool.read { db in try Row.fetchOne(db, sql: "SELECT json, fetched_at FROM cache WHERE key = ?", arguments: [key]) }
        guard let row else { return nil }
        let fetchedAtRaw: String = row["fetched_at"]
        guard let at = try? Date(fetchedAtRaw, strategy: .iso8601) else { return nil }
        return CacheHit(value: try JSON.decoder.decode(T.self, from: row["json"]), fetchedAt: at)
    }

    public func fetchedAt(_ key: String) throws -> Date? {
        let raw: String? = try db.pool.read { db in try String.fetchOne(db, sql: "SELECT fetched_at FROM cache WHERE key = ?", arguments: [key]) }
        guard let raw else { return nil }
        return try? Date(raw, strategy: .iso8601)
    }

    /// Clears all cached entries. Call this when the active provider's identity changes
    /// (e.g. hub base URL re-pointed) so stale data from the previous provider is never
    /// served under a new identity (parity with RN, which clears its cache on this event).
    public func clear() throws {
        try db.pool.write { db in
            try db.execute(sql: "DELETE FROM cache")
        }
    }
}

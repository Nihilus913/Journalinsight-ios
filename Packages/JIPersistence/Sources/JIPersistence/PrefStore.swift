import Foundation
import GRDB
import JICore

public struct PrefStore: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    public func set<T: Encodable>(_ key: String, _ value: T) throws {
        let blob = try JSON.encoder.encode(value)
        let now = Date().ISO8601Format()
        try db.pool.write { db in try db.execute(sql: "INSERT OR REPLACE INTO pref(key, json, updated_at) VALUES (?, ?, ?)", arguments: [key, blob, now]) }
    }

    public func get<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        let blob: Data? = try db.pool.read { db in try Data.fetchOne(db, sql: "SELECT json FROM pref WHERE key = ?", arguments: [key]) }
        return try blob.map { try JSON.decoder.decode(T.self, from: $0) }
    }

    public func remove(_ key: String) throws {
        try db.pool.write { db in try db.execute(sql: "DELETE FROM pref WHERE key = ?", arguments: [key]) }
    }
}

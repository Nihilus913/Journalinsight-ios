import Foundation
import GRDB

/// One pool per file. `journalinsight.sqlite` = backed-up user data; `cache.sqlite` = disposable
/// server cache (excluded from backup, exactly like RN's manifest.ts).
public final class AppDatabase: Sendable {
    public let pool: DatabasePool

    private init(pool: DatabasePool) throws {
        self.pool = pool
        try Migrations.migrator.migrate(pool)
    }

    /// A disposable store for tests. `DatabasePool` cannot open the special `":memory:"`
    /// path — it needs a real file on disk to back its WAL mode — so this opens a
    /// `DatabasePool` on a uniquely-named temp file instead. Despite the name (kept as the
    /// frozen public API), this is a temp-file pool, not a true in-memory database; each
    /// call gets its own file, so two `inMemory()` stores never share state.
    public static func inMemory() throws -> AppDatabase {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("journalinsight-test-\(UUID().uuidString).sqlite")
            .path
        return try AppDatabase(pool: DatabasePool(path: path))
    }

    public static func onDisk(name: String = "journalinsight.sqlite") throws -> AppDatabase {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        return try AppDatabase(pool: DatabasePool(path: dir.appending(path: name).path, configuration: config))
    }

    public static func cache() throws -> AppDatabase { try onDisk(name: "cache.sqlite") }
}

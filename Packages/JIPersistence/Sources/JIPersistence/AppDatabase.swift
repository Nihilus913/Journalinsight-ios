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

    /// Opens (or creates) `name` under Application Support. Pass `excludedFromBackup: true`
    /// for disposable stores so iCloud/iTunes backups skip the file and its WAL/SHM siblings.
    public static func onDisk(name: String = "journalinsight.sqlite", excludedFromBackup: Bool = false) throws -> AppDatabase {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try open(at: dir.appending(path: name), excludedFromBackup: excludedFromBackup)
    }

    /// The disposable server cache — never backed up, mirroring RN's manifest split.
    public static func cache() throws -> AppDatabase { try onDisk(name: "cache.sqlite", excludedFromBackup: true) }

    /// Internal so tests can exercise the backup flag against a temp path instead of the
    /// real Application Support directory.
    static func open(at url: URL, excludedFromBackup: Bool) throws -> AppDatabase {
        var config = Configuration()
        config.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }
        let db = try AppDatabase(pool: DatabasePool(path: url.path, configuration: config))
        if excludedFromBackup {
            // The pool has opened the file (and WAL mode created -wal/-shm), so the flag sticks.
            for suffix in ["", "-wal", "-shm"] {
                var sibling = URL(filePath: url.path + suffix)
                guard FileManager.default.fileExists(atPath: sibling.path) else { continue }
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try sibling.setResourceValues(values)
            }
        }
        return db
    }
}

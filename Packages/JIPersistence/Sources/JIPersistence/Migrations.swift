import GRDB

/// One migrator shared by both database files (`journalinsight.sqlite` and `cache.sqlite`).
/// Both tables are created in both files; each store (`OfflineCache`, `PrefStore`) only
/// touches its own table. Keeping one migrator avoids versioning two separate schemas.
///
/// `eraseDatabaseOnSchemaChange` is left at its default (`false`) — never erase on schema
/// drift, since the Fold-import path depends on stable schemas. Later waves append
/// migrations to this migrator; never edit a migration that has already shipped.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1_foundation") { db in
            try db.create(table: "cache", ifNotExists: true) { t in
                t.primaryKey("key", .text)
                t.column("json", .blob).notNull()
                t.column("fetched_at", .text).notNull()
            }
            try db.create(table: "pref", ifNotExists: true) { t in
                t.primaryKey("key", .text)
                t.column("json", .blob).notNull()
                t.column("updated_at", .text).notNull()
            }
        }
        // W3b-L4 (P-weigh-in): a durable write queue for offline-first writes. `outbox` is its
        // own table (not reusing `cache`/`pref`) since rows here are mutated in place (`attempts`,
        // `last_error`) rather than replaced wholesale. See `Outbox.swift`.
        m.registerMigration("v2_outbox") { db in
            try db.create(table: "outbox", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("kind", .text).notNull()
                t.column("payload", .blob).notNull()
                t.column("created_at", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
            }
        }
        return m
    }
}

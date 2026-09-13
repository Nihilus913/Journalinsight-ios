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
        return m
    }
}

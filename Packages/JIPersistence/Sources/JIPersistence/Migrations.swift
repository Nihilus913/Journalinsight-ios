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
        // W4-L0 (P-vault + the W4 schema): the 8 capture tables, column names
        // taken verbatim from the RN oracle so a Fold-archive row imports
        // without any renaming (mobile/src/journal/schema.ts,
        // mobile/src/mind/{checkins,events,who5}.ts,
        // mobile/src/goals/GoalStore.ts). Vaulted columns (sealed via
        // JIVault's FieldCipher — spec §5.4, encrypt-from-day-one) stay
        // plain TEXT here: they hold envelope strings, not typed values, so
        // GRDB never needs to know they're encrypted.
        m.registerMigration("v3_capture") { db in
            // entries / tags / entry_tags — mobile/src/journal/schema.ts.
            // Vaulted: text, mood.
            try db.create(table: "entries", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull()
                t.column("ts", .text).notNull()
                t.column("text", .text).notNull()
                t.column("duration_sec", .integer).notNull().defaults(to: 0)
                t.column("mood", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
                t.column("synced", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "tags", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
            }
            try db.create(table: "entry_tags", ifNotExists: true) { t in
                t.column("entry_id", .integer).notNull()
                t.column("tag_id", .integer).notNull()
                t.primaryKey(["entry_id", "tag_id"])
            }

            // mind_checkin — mobile/src/mind/checkins.ts. Vaulted: mood,
            // stress, energy, dosed, irritability, restlessness, appetite,
            // note (E13-7 extended scope — every column but date/timestamps/
            // synced).
            try db.create(table: "mind_checkin", ifNotExists: true) { t in
                t.primaryKey("date", .text)
                t.column("mood", .text)
                t.column("stress", .text).notNull()
                t.column("energy", .text).notNull()
                t.column("dosed", .text).notNull().defaults(to: "0")
                t.column("irritability", .text)
                t.column("restlessness", .text)
                t.column("appetite", .text)
                t.column("note", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
                t.column("synced", .integer).notNull().defaults(to: 0)
            }

            // mind_event — mobile/src/mind/events.ts. Vaulted: type,
            // prodrome, severity (spec §5.4) plus triggers/note (E13-7).
            try db.create(table: "mind_event", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull()
                t.column("time_local", .text).notNull()
                t.column("type", .text).notNull()
                t.column("severity", .text).notNull()
                t.column("prodrome", .text).notNull().defaults(to: "[]")
                t.column("triggers", .text).notNull().defaults(to: "")
                t.column("note", .text)
                t.column("created_at", .text).notNull()
                t.column("synced", .integer).notNull().defaults(to: 0)
            }

            // mind_who5 — mobile/src/mind/who5.ts. Vaulted: i1-i5, raw, pct
            // (every column — Art.9 depression-screening signal).
            try db.create(table: "mind_who5", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull()
                t.column("i1", .text).notNull()
                t.column("i2", .text).notNull()
                t.column("i3", .text).notNull()
                t.column("i4", .text).notNull()
                t.column("i5", .text).notNull()
                t.column("raw", .text).notNull()
                t.column("pct", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("synced", .integer).notNull().defaults(to: 0)
            }

            // goals + goal_targets_mirror — mobile/src/goals/GoalStore.ts.
            // Neither is vaulted (ad-hoc freeform list; structured mirror of
            // the hub's GET/PUT /planning/goals document).
            try db.create(table: "goals", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("target_date", .text)
                t.column("progress", .double).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
            }
            try db.create(table: "goal_targets_mirror", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("weight_base_kg", .double)
                t.column("weight_target_kg", .double).notNull()
                t.column("weight_target_date", .text)
                t.column("strength_json", .text).notNull()
                t.column("steps_daily", .integer)
                t.column("kcal_goal", .integer)
                t.column("protein_g", .integer)
                t.column("carbs_g", .integer)
                t.column("fat_g", .integer)
                t.column("synced_at", .text).notNull()
            }
        }
        return m
    }
}

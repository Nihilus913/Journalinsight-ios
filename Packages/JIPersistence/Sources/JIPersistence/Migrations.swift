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
        // W5b-L4 (P-gate-respond + P-local-mirrors): `decision_log_mirror`, the local-first record
        // of every gate answer. Column names verbatim from the RN oracle
        // (mobile/src/decisions/DecisionLogStore.ts), which in turn mirrors the server table
        // plan.decision_log (app/db/migrations/002_plan_schema.sql: logged_at, window_days,
        // recommendation, user_choice, override_reason) — so a Fold-archive row imports without
        // renaming. Unlike goal_targets_mirror/KPI/challenges this is NOT a refresh-mirror: the
        // hub has no GET that reads decision_log back (only POST /planning/gate/respond writes
        // one), so rows are written locally first and `remote_log_id`/`synced` are filled in once
        // that POST confirms. Nothing is vaulted here (no Art.9 content).
        m.registerMigration("v4_decision_log") { db in
            try db.create(table: "decision_log_mirror", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("remote_log_id", .integer)
                t.column("logged_at", .text).notNull()
                t.column("window_days", .integer).notNull()
                t.column("recommendation", .text).notNull()
                t.column("user_choice", .text).notNull()
                t.column("override_reason", .text)
                t.column("synced", .integer).notNull().defaults(to: 0)
            }
        }
        // W-B38-A A-7: the iPhone strength logger, LOCAL-FIRST (the hub's plan.strength_session /
        // plan.strength_set_log, migration 059, mirror these rows once the `strength` outbox
        // drains). Keyed by client UUIDs so a replayed write is idempotent on both sides; a set
        // hangs off its session's client_id (the hub id may not exist yet while offline).
        // NOT the UserDefaults `StrengthStateStore` (that one holds progression TARGETS).
        m.registerMigration("v5_strength_log") { db in
            try db.create(table: "strength_session_log", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("client_id", .text).notNull().unique()
                t.column("remote_id", .integer)
                t.column("session_id", .integer)
                t.column("session_name", .text)
                t.column("date", .text).notNull()
                t.column("started_at", .text).notNull()
                t.column("ended_at", .text)
            }
            try db.create(table: "strength_set_log", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("client_id", .text).notNull().unique()
                t.column("session_client_id", .text).notNull()
                    .references("strength_session_log", column: "client_id", onDelete: .cascade)
                t.column("exercise_key", .text).notNull()
                t.column("exercise_id", .integer)
                t.column("set_index", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("reps", .integer)
                t.column("weight_kg", .double)
                t.column("duration_s", .integer)
                t.column("rpe", .double)
                t.column("performed_at", .text).notNull()
            }
            try db.create(index: "strength_set_log_session", on: "strength_set_log", columns: ["session_client_id"], ifNotExists: true)
        }
        // W-B38-B B-2: the Watch's saved HKWorkout uuid on the session (hub: plan.strength_session.hk_workout_uuid).
        m.registerMigration("v5b_strength_hk_workout") { db in
            try db.alter(table: "strength_session_log") { t in t.add(column: "hk_workout_uuid", .text) }
        }
        // W-B92 C-4 (Toby Q3 2026-10-04): what was planned each day, kept on the phone so the
        // Training Calendar (and the hub-less B-50 path) shows history as planned. One row per
        // date, first write wins (`PlannedSnapshotStore`); the hub's twin is plan.planned_snapshot (HT 075).
        m.registerMigration("v6_b92_planned_snapshot") { db in
            try db.create(table: "planned_snapshot", ifNotExists: true) { t in
                t.column("date", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("session_type", .text)
                t.column("prescription", .text)
                t.column("origin", .text).notNull()
                t.column("template_id", .integer)
                t.column("captured_at", .text).notNull()
            }
        }
        // W-ONDEVICE O-6 (B-20): raw nightly values behind the on-device verdict. Recompute-on-read
        // (no aggregate columns); `(source, metric, date)` keeps a replayed night one row.
        // Not backed up: rebuildable from HealthKit + the hub seed.
        m.registerMigration("v6_ondevice_baseline") { db in
            try db.create(table: "baseline_sample", ifNotExists: true) { t in
                t.column("source", .text).notNull()
                t.column("metric", .text).notNull()
                t.column("date", .text).notNull()
                t.column("value", .double).notNull()
                t.primaryKey(["source", "metric", "date"])
            }
        }
        // W-ONDEVICE O-10 (B-44): the dual-run log — one row per morning, on-device vs hub verdict.
        // Local diagnostics only (not backed up).
        m.registerMigration("v6b_ondevice_shadow") { db in
            try db.create(table: "ondevice_shadow_log", ifNotExists: true) { t in
                t.primaryKey("day", .text)
                t.column("ondevice_verdict", .text).notNull()
                t.column("hub_verdict", .text)
                t.column("inputs_digest", .text).notNull()
                t.column("computed_at", .text).notNull()
                t.column("latency_from_wake_sec", .double)
            }
        }
        return m
    }
}

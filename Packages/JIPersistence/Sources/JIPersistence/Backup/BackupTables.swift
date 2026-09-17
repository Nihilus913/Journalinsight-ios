import Foundation

/// One table this device knows how to back up/restore, plus which of its
/// columns are vaulted (sealed via `JIVault`'s `FieldCipher`) as of `v3_capture`
/// (`Migrations.swift`). Mirrors RN `manifest.ts`'s `BACKUP_TABLES`, scoped to
/// the tables W4 actually created — see `notYetMigrated` below for the rest of
/// RN's manifest.
public struct BackupTableSpec: Sendable, Equatable {
    public let table: String
    public let vaultedColumns: Set<String>

    public init(table: String, vaultedColumns: Set<String> = []) {
        self.table = table
        self.vaultedColumns = vaultedColumns
    }
}

/// Card-scoped manifest + a "not yet" list for W5. Deliberately NOT
/// generic/schema-agnostic the way RN's dump.ts is — `v3_capture` is the only
/// migration this app has, so hardcoding its 8 tables here is simpler than a
/// generic sqlite introspection layer, and any table this device's schema
/// doesn't know about goes straight to `notYetMigrated`'s bucket instead.
public enum BackupTables {
    /// The 8 tables `Migrations.swift`'s `v3_capture` creates, column names
    /// verbatim from the RN oracle (`journal/schema.ts`, `mind/{checkins,
    /// events,who5}.ts`, `goals/GoalStore.ts`). Vaulted-column sets match
    /// `Migrations.swift`'s own per-table comments (spec §5.4,
    /// encrypt-from-day-one).
    public static let v1: [BackupTableSpec] = [
        BackupTableSpec(table: "entries", vaultedColumns: ["text", "mood"]),
        BackupTableSpec(table: "tags"),
        BackupTableSpec(table: "entry_tags"),
        BackupTableSpec(table: "mind_checkin", vaultedColumns: [
            "mood", "stress", "energy", "dosed", "irritability", "restlessness", "appetite", "note",
        ]),
        BackupTableSpec(table: "mind_event", vaultedColumns: ["type", "prodrome", "severity"]),
        BackupTableSpec(table: "mind_who5", vaultedColumns: ["i1", "i2", "i3", "i4", "i5", "raw", "pct"]),
        BackupTableSpec(table: "goals"),
        BackupTableSpec(table: "goal_targets_mirror"),
    ]

    public static func spec(for table: String) -> BackupTableSpec? {
        v1.first { $0.table == table }
    }

    /// Tables RN's `manifest.ts` backs up that `v3_capture` hasn't created
    /// yet (kpi/challenges/decision mirrors, gate_* rows, local_prefs'
    /// `cache`, deep-history rows, `strength_state_local`) — PARITY says
    /// these land in W5. A Fold archive carrying one of these is neither
    /// silently dropped nor treated as an error: `BackupImporter` lists it
    /// in the restore preview as "migrates in W5" and does not write it.
    public static let notYetMigrated: Set<String> = [
        "kpi_targets_mirror", "challenges_mirror", "decision_log_mirror",
        "gate_state", "gate_verdict_log", "gate_respond_local", "session_feel_local",
        "cache", "history_rows", "history_progress", "history_samples",
        "strength_state_local",
    ]
}

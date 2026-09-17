import Testing
import GRDB
@testable import JIPersistence

/// W4-L0 exit criterion: `v3_capture` creates all 8 tables, with the RN
/// column names verbatim (see `Migrations.swift`'s `v3_capture` comment for
/// the oracle file each table mirrors).
@Test func v3CaptureCreatesAllEightTables() throws {
    let db = try AppDatabase.inMemory()
    try db.pool.read { conn in
        let expected: [String: Set<String>] = [
            "entries": ["id", "date", "ts", "text", "duration_sec", "mood", "created_at", "updated_at", "synced"],
            "tags": ["id", "name"],
            "entry_tags": ["entry_id", "tag_id"],
            "mind_checkin": ["date", "mood", "stress", "energy", "dosed", "irritability", "restlessness", "appetite", "note", "created_at", "updated_at", "synced"],
            "mind_event": ["id", "date", "time_local", "type", "severity", "prodrome", "triggers", "note", "created_at", "synced"],
            "mind_who5": ["id", "date", "i1", "i2", "i3", "i4", "i5", "raw", "pct", "created_at", "synced"],
            "goals": ["id", "title", "target_date", "progress", "created_at"],
            "goal_targets_mirror": ["id", "weight_base_kg", "weight_target_kg", "weight_target_date", "strength_json", "steps_daily", "kcal_goal", "protein_g", "carbs_g", "fat_g", "synced_at"],
        ]
        for (table, expectedColumns) in expected {
            #expect(try conn.tableExists(table), "missing table \(table)")
            let columns = Set(try conn.columns(in: table).map(\.name))
            #expect(columns == expectedColumns, "column mismatch for \(table): got \(columns)")
        }
    }
}

/// Vaulted columns hold envelope strings, not typed values — every column
/// the W4 card names as vaulted must be TEXT, even where RN's own schema
/// used INTEGER (mind_event.severity — see Migrations.swift comment).
@Test func vaultedColumnsAreText() throws {
    let db = try AppDatabase.inMemory()
    try db.pool.read { conn in
        let textColumns: [(table: String, column: String)] = [
            ("entries", "text"), ("entries", "mood"),
            ("mind_checkin", "mood"), ("mind_checkin", "note"),
            ("mind_event", "type"), ("mind_event", "prodrome"), ("mind_event", "severity"),
        ]
        for (table, column) in textColumns {
            let columns = try conn.columns(in: table)
            let match = columns.first { $0.name == column }
            #expect(match?.type.uppercased() == "TEXT", "\(table).\(column) should be TEXT")
        }
    }
}

import Foundation
import GRDB
import JICore

/// W-B92 C-4 (Toby Q3 2026-10-04) — the phone's daily snapshot of the planned session
/// (`planned_snapshot`, migration `v6_b92_planned_snapshot`). First write of a date wins and a
/// future date is never written, so a later plan edit cannot re-type history. Filled from every
/// hub calendar month the app sees (`recordMonth`) and from today's resolved session; read back
/// with `source == "device"` when the hub cannot answer (offline / 404 / the hub-less B-50 path).
public struct PlannedSnapshotStore: Sendable {
    private let db: AppDatabase
    public init(db: AppDatabase) { self.db = db }

    /// Stores `planned` for `iso` unless the date already has a snapshot or lies after `today`.
    /// true = a row was written.
    @discardableResult
    public func record(_ planned: TrainingCalendarPlanned, on iso: String, today: String) throws -> Bool {
        guard iso <= today else { return false }
        let now = Date().ISO8601Format()
        return try db.pool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO planned_snapshot (date, name, type, session_type, prescription, origin, template_id, captured_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [iso, planned.name, planned.type, planned.sessionType, planned.prescription,
                                 planned.source, planned.templateId, now])
            return db.changesCount == 1
        }
    }

    /// Backfills every day of a hub month up to its `today` (once — existing dates are kept).
    /// Returns the number of rows written.
    @discardableResult
    public func recordMonth(_ month: TrainingCalendarMonth) throws -> Int {
        try month.days.reduce(0) { n, d in n + (try record(d.planned, on: d.date, today: month.today) ? 1 : 0) }
    }

    /// date → planned for every snapshot in [from, to] (ISO dates, inclusive), source "device".
    public func snapshots(from: String, to: String) throws -> [String: TrainingCalendarPlanned] {
        try db.pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT date, name, type, session_type, prescription, template_id FROM planned_snapshot
                WHERE date BETWEEN ? AND ? ORDER BY date
                """, arguments: [from, to])
            var out: [String: TrainingCalendarPlanned] = [:]
            for r in rows {
                out[r["date"]] = TrainingCalendarPlanned(name: r["name"], type: r["type"], sessionType: r["session_type"],
                                                         prescription: r["prescription"], source: "device", templateId: r["template_id"])
            }
            return out
        }
    }
}

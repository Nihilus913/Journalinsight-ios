import Foundation
import GRDB
import JICore
import Testing
@testable import JIPersistence

/// W-B92 C-4 (Toby Q3 2026-10-04) — `PlannedSnapshotStore` over `v6_b92_planned_snapshot`: the
/// phone's own record of what was planned each day (the on-device B-50 path). First write of a
/// date wins; future dates are refused; a hub month backfills past + today once.
@Suite struct PlannedSnapshotStoreTests {
    let store: PlannedSnapshotStore
    let db: AppDatabase
    init() throws { db = try AppDatabase.inMemory(); store = PlannedSnapshotStore(db: db) }

    static func p(_ name: String, _ type: String = "strength", source: String = "plan") -> TrainingCalendarPlanned {
        TrainingCalendarPlanned(name: name, type: type, prescription: name, source: source)
    }

    @Test func migrationCreatesTheTable() throws {
        let cols = try db.pool.read { db in try db.columns(in: "planned_snapshot").map(\.name) }
        #expect(cols == ["date", "name", "type", "session_type", "prescription", "origin", "template_id", "captured_at"])
    }

    @Test func firstWriteWins() throws {
        #expect(try store.record(Self.p("Day 1 Full Upper + Z2 40min"), on: "2026-10-05", today: "2026-10-05"))
        #expect(try !store.record(Self.p("Norwegian 4x4 intervals", "interval"), on: "2026-10-05", today: "2026-10-05"))
        let got = try #require(try store.snapshots(from: "2026-10-01", to: "2026-10-31")["2026-10-05"])
        #expect(got.name == "Day 1 Full Upper + Z2 40min" && got.type == "strength" && got.source == "device")
    }

    @Test func futureDatesAreRefused() throws {
        #expect(try !store.record(Self.p("x"), on: "2026-10-06", today: "2026-10-05"))
        #expect(try store.snapshots(from: "2026-10-01", to: "2026-10-31").isEmpty)
    }

    @Test func aHubMonthBackfillsPastAndTodayOnly() throws {
        let days = ["2026-10-03", "2026-10-04", "2026-10-05"].map {
            TrainingCalendarDay(date: $0, planned: Self.p("S \($0)", source: "snapshot"), state: .planned)
        }
        let month = TrainingCalendarMonth(month: "2026-10", today: "2026-10-04", syncedThrough: nil, days: days,
                                          summary: TrainingCalendarSummary(days: days))
        #expect(try store.recordMonth(month) == 2)
        #expect(try store.recordMonth(month) == 0)                 // idempotent
        #expect(try store.snapshots(from: "2026-10-01", to: "2026-10-31").keys.sorted() == ["2026-10-03", "2026-10-04"])
    }

    @Test func rangeIsInclusiveAndBounded() throws {
        for d in ["2026-09-30", "2026-10-01", "2026-10-31", "2026-11-01"] { _ = try store.record(Self.p(d), on: d, today: "2026-12-01") }
        #expect(try store.snapshots(from: "2026-10-01", to: "2026-10-31").keys.sorted() == ["2026-10-01", "2026-10-31"])
    }
}

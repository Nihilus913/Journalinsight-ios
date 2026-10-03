import Foundation
import GRDB
import Testing
@testable import JIPersistence

/// W-B38-A A-7 — `StrengthSessionLogStore` over `v5_strength_log`. Local-first: every call here is
/// a plain SQLite read/write; the type has no hub/provider dependency to touch.
@Suite struct StrengthSessionLogStoreTests {
    let store: StrengthSessionLogStore
    let db: AppDatabase
    init() throws { db = try AppDatabase.inMemory(); store = StrengthSessionLogStore(db: db) }

    func session(_ id: String = "s-1", date: String = "2026-10-03") -> StrengthSessionLog {
        StrengthSessionLog(clientId: id, sessionId: 1, sessionName: "Upper A", date: date, startedAt: "\(date)T07:00:00Z")
    }

    func set(_ id: String, _ idx: Int, kg: Double = 50, reps: Int = 8, session: String = "s-1", key: String = "Barbell Bench Press") -> StrengthSetLog {
        StrengthSetLog(clientId: id, sessionClientId: session, exerciseKey: key, exerciseId: 7, setIndex: idx,
                       reps: reps, weightKg: kg, rpe: 8, performedAt: "2026-10-03T07:0\(idx):00Z")
    }

    @Test func v5MigrationCreatesBothTables() throws {
        let (s, x) = try db.pool.read { db in
            (try db.columns(in: "strength_session_log").map(\.name), try db.columns(in: "strength_set_log").map(\.name))
        }
        #expect(s == ["id", "client_id", "remote_id", "session_id", "session_name", "date", "started_at", "ended_at"])
        #expect(x == ["id", "client_id", "session_client_id", "exercise_key", "exercise_id", "set_index", "kind",
                      "reps", "weight_kg", "duration_s", "rpe", "performed_at"])
    }

    @Test func insertSetThenReadItBack() throws {
        try store.startSession(session())
        try store.upsertSet(set("a", 1))
        try store.upsertSet(set("b", 2, kg: 52.5))
        let sets = try store.sets(sessionClientId: "s-1")
        #expect(sets.map(\.clientId) == ["a", "b"])
        #expect(sets[1].weightKg == 52.5 && sets[1].reps == 8 && sets[1].rpe == 8 && sets[1].kind == .reps)
        #expect(try store.openSession(date: "2026-10-03")?.clientId == "s-1")
    }

    @Test func editSetChangesItInPlace() throws {
        try store.startSession(session())
        try store.upsertSet(set("a", 1))
        try store.upsertSet(set("a", 1, kg: 55, reps: 6))
        let sets = try store.sets(sessionClientId: "s-1")
        #expect(sets.count == 1)
        #expect(sets[0].weightKg == 55 && sets[0].reps == 6)
    }

    @Test func deleteSetRemovesOnlyThatSet() throws {
        try store.startSession(session())
        try store.upsertSet(set("a", 1)); try store.upsertSet(set("b", 2))
        try store.deleteSet(clientId: "a")
        #expect(try store.sets(sessionClientId: "s-1").map(\.clientId) == ["b"])
    }

    @Test func startingTheSameSessionTwiceKeepsOneRow() throws {
        try store.startSession(session())
        try store.startSession(session())
        #expect(try store.sessions(from: "2026-10-01", to: "2026-10-31").count == 1)
    }

    @Test func completeClosesTheOpenSessionAndRemoteIdAttaches() throws {
        try store.startSession(session())
        try store.setRemoteId(sessionClientId: "s-1", remoteId: 41)
        try store.complete(sessionClientId: "s-1", endedAt: "2026-10-03T08:00:00Z")
        #expect(try store.openSession(date: "2026-10-03") == nil)
        let s = try #require(try store.session(clientId: "s-1"))
        #expect(s.remoteId == 41 && s.isComplete)
    }

    @Test func historyIsNewestFirstWithinTheRange() throws {
        try store.startSession(session("old", date: "2026-09-20"))
        try store.startSession(session("mid", date: "2026-09-27"))
        try store.startSession(session("new", date: "2026-10-03"))
        #expect(try store.sessions(from: "2026-09-21", to: "2026-10-31").map(\.clientId) == ["new", "mid"])
    }

    @Test func lastSetsComeFromTheLatestEarlierSessionOfThatExercise() throws {
        try store.startSession(session("w1", date: "2026-09-26"))
        try store.upsertSet(set("w1a", 1, kg: 47.5, session: "w1"))
        try store.startSession(session("w2", date: "2026-09-29"))
        try store.upsertSet(set("w2a", 1, kg: 50, session: "w2"))
        try store.upsertSet(set("w2r", 1, kg: 40, session: "w2", key: "Barbell Row"))
        try store.startSession(session("today", date: "2026-10-03"))
        try store.upsertSet(set("t1", 1, kg: 52.5, session: "today"))
        let last = try store.lastSets(exerciseKey: "Barbell Bench Press", before: "2026-10-03")
        #expect(last.map(\.clientId) == ["w2a"])
    }

    @Test func hubMergeUpsertsOnClientIdsAndNeverDropsLocalRows() throws {
        try store.startSession(session())
        try store.upsertSet(set("local-only", 1))
        var hubSession = session(); hubSession.remoteId = 9; hubSession.endedAt = "2026-10-03T08:00:00Z"
        try store.mergeFromHub([(hubSession, [set("hub-a", 2, kg: 60)])])
        try store.mergeFromHub([(hubSession, [set("hub-a", 2, kg: 60)])])
        #expect(try store.sets(sessionClientId: "s-1").map(\.clientId) == ["local-only", "hub-a"])
        #expect(try store.session(clientId: "s-1")?.remoteId == 9)
    }

    @Test func timedSetsKeepTheirDuration() throws {
        try store.startSession(session())
        try store.upsertSet(StrengthSetLog(clientId: "p", sessionClientId: "s-1", exerciseKey: "Plank", setIndex: 1,
                                           kind: .timed, durationS: 45, performedAt: "2026-10-03T07:30:00Z"))
        let p = try #require(try store.sets(sessionClientId: "s-1").first)
        #expect(p.kind == .timed && p.durationS == 45 && p.reps == nil && p.weightKg == nil)
    }
}

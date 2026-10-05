import Foundation
import Testing
import GRDB
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX-P0 RG-01 (B-117): the app opened ~10 independent `DatabasePool`s on
/// `journalinsight.sqlite`; concurrent writers across them hit SQLITE_BUSY and the logger's
/// `try? store.startSession` swallowed it, so 'Log set' silently wrote nothing. Now every
/// `onDisk`/`shared(at:)` caller gets ONE shared pool (busy timeout), and a failed session start
/// surfaces an error instead of writing an orphan set.
@MainActor @Suite(.serialized) struct B117SharedPoolTests {
    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("b117-\(UUID().uuidString).sqlite")
    }

    @Test func sharedReturnsOnePoolPerFile() throws {
        let url = Self.tempURL()
        let a = try AppDatabase.shared(at: url)
        let b = try AppDatabase.shared(at: url)
        #expect(a === b)
        #expect(try AppDatabase.shared(at: Self.tempURL()) !== a)
    }

    @Test func eightConcurrentWritersNeverHitBusy() async throws {
        let url = Self.tempURL()
        let session = StrengthSessionLog(date: "2026-10-05", startedAt: "2026-10-05T18:00:00Z")
        try StrengthSessionLogStore(db: AppDatabase.shared(at: url)).startSession(session)
        let errors = await withTaskGroup(of: [String].self) { group in
            for w in 0..<8 {
                group.addTask { @Sendable in
                    var errs: [String] = []
                    for i in 0..<50 {
                        do {
                            // Each writer resolves the database itself, the way the ~10 app call sites do.
                            let store = try StrengthSessionLogStore(db: AppDatabase.shared(at: url))
                            try store.upsertSet(StrengthSetLog(sessionClientId: session.clientId, exerciseKey: "W\(w)",
                                                               setIndex: i + 1, reps: 8, weightKg: 50,
                                                               performedAt: "2026-10-05T18:00:00Z"))
                        } catch { errs.append(String(describing: error)) }
                    }
                    return errs
                }
            }
            var all: [String] = []
            for await e in group { all += e }
            return all
        }
        #expect(errors.isEmpty, "\(errors.count) errors, first: \(errors.first ?? "")")
        #expect(errors.filter { $0.contains("SQLITE_BUSY") || $0.contains("database is locked") }.isEmpty)
        let rows = try await AppDatabase.shared(at: url).pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM strength_set_log") }
        #expect(rows == 400)
    }

    @Test func failedSessionStartSurfacesAnErrorAndWritesNoSet() throws {
        let db = try AppDatabase.inMemory()
        try db.pool.write { db in
            try db.execute(sql: """
                CREATE TRIGGER b117_fail BEFORE INSERT ON strength_session_log
                BEGIN SELECT RAISE(ABORT, 'database is locked'); END
                """)
        }
        let outbox = Outbox(db: db)
        let bench = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "12",
                                    currentKg: 50, stepKg: 2.5, nextKg: 50)
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let m = StrengthLogViewModel(lifts: [bench], sessionId: 1, sessionName: "Upper A", store: StrengthSessionLogStore(db: db),
                                     outbox: outbox, provider: StrengthFakeHub(), prefs: PrefStore(db: db),
                                     today: { "2026-10-05" }, now: { t })
        let logged = m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 12)
        #expect(logged == nil)
        #expect(m.error != nil)
        #expect(m.session == nil)
        #expect(m.timer.phase != .resting)   // no rest started for a set that was not saved
        let sets = try db.pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM strength_set_log") }
        #expect(sets == 0)
        #expect(try outbox.pending().isEmpty)   // no createSession / logSet queued for the hub
    }

    @Test func threeSetsLogOnTheSharedPool() throws {
        let db = try AppDatabase.shared(at: Self.tempURL())
        let outbox = Outbox(db: db)
        let bench = StrengthLogLift(exerciseId: 7, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "12",
                                    currentKg: 50, stepKg: 2.5, nextKg: 50)
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let m = StrengthLogViewModel(lifts: [bench], sessionId: 1, sessionName: "Upper A", store: StrengthSessionLogStore(db: db),
                                     outbox: outbox, provider: StrengthFakeHub(), prefs: PrefStore(db: db),
                                     today: { "2026-10-05" }, now: { t })
        for _ in 0..<3 { #expect(m.logSet(exerciseKey: "Barbell Bench Press", weightKg: 50, reps: 12) != nil) }
        #expect(m.error == nil)
        #expect(m.cards[0].sets.count == 3)
        #expect(m.timer.phase == .resting)
        #expect(try outbox.pending().count == 4)   // createSession + 3 logSet
    }
}

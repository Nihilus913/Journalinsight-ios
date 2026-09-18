import Foundation
import GRDB
import Testing
@testable import JIPersistence

/// W5b-L4 — `DecisionLogStore` over `decision_log_mirror` (`v4_decision_log`). Port of the RN
/// oracle's `mobile/src/decisions/DecisionLogStore.ts` behaviour (its own suite lives at
/// `mobile/__tests__/decisions/decisionLogStore.test.ts`).

private func entry(
    loggedAt: String, choice: String = "y", recommendation: String = "PROGRESS",
    windowDays: Int = 7, overrideReason: String? = nil
) -> NewDecisionLogEntry {
    NewDecisionLogEntry(
        loggedAt: loggedAt, windowDays: windowDays, recommendation: recommendation,
        userChoice: choice, overrideReason: overrideReason
    )
}

@Test func v4MigrationCreatesDecisionLogMirrorWithTheOraclesColumns() throws {
    let db = try AppDatabase.inMemory()
    let columns = try db.pool.read { db in try db.columns(in: "decision_log_mirror").map(\.name) }
    #expect(columns == ["id", "remote_log_id", "logged_at", "window_days", "recommendation", "user_choice", "override_reason", "synced"])
}

@Test func appendRecordsAnUnsyncedRowBeforeAnyHubPost() throws {
    let store = DecisionLogStore(db: try AppDatabase.inMemory())
    let id = try store.append(entry(loggedAt: "2026-09-18T07:00:00Z"))

    let rows = try store.recent(limit: 10)
    #expect(rows.count == 1)
    #expect(rows[0].id == id)
    #expect(rows[0].remoteLogId == nil)
    #expect(rows[0].synced == false)
    #expect(rows[0].recommendation == "PROGRESS")
    #expect(rows[0].userChoice == "y")
    #expect(rows[0].overrideReason == nil)
    #expect(rows[0].windowDays == 7)
}

@Test func appendKeepsTheOverrideReasonVerbatim() throws {
    let store = DecisionLogStore(db: try AppDatabase.inMemory())
    try store.append(entry(loggedAt: "2026-09-18T07:00:00Z", choice: "override", recommendation: "REDUCE", overrideReason: "Schedule constraint"))
    #expect(try store.recent(limit: 1)[0].overrideReason == "Schedule constraint")
}

@Test func markSyncedAttachesTheHubsLogIdAndFlipsSynced() throws {
    let store = DecisionLogStore(db: try AppDatabase.inMemory())
    let id = try store.append(entry(loggedAt: "2026-09-18T07:00:00Z"))
    try store.markSynced(localId: id, remoteLogId: 42)

    let row = try store.recent(limit: 1)[0]
    #expect(row.remoteLogId == 42)
    #expect(row.synced == true)
    #expect(try store.pendingSync().isEmpty)
}

/// The hub's `GateRespondOut.log_id` is `number | null` in the oracle's own type — a confirmed
/// write with a null id still leaves the row synced, and `remoteLogId` stays nil rather than 0.
@Test func markSyncedAcceptsANullRemoteId() throws {
    let store = DecisionLogStore(db: try AppDatabase.inMemory())
    let id = try store.append(entry(loggedAt: "2026-09-18T07:00:00Z"))
    try store.markSynced(localId: id, remoteLogId: nil)

    let row = try store.recent(limit: 1)[0]
    #expect(row.remoteLogId == nil)
    #expect(row.synced == true)
    #expect(try store.pendingSync().isEmpty)
}

@Test func recentIsNewestFirstAndCapped() throws {
    let store = DecisionLogStore(db: try AppDatabase.inMemory())
    for i in 1...5 { try store.append(entry(loggedAt: "2026-09-1\(i)T07:00:00Z")) }

    let rows = try store.recent(limit: 3)
    #expect(rows.count == 3)
    #expect(rows.map(\.loggedAt) == ["2026-09-15T07:00:00Z", "2026-09-14T07:00:00Z", "2026-09-13T07:00:00Z"])
}

@Test func listAllReturnsEveryRowNewestFirst() throws {
    let store = DecisionLogStore(db: try AppDatabase.inMemory())
    for i in 1...5 { try store.append(entry(loggedAt: "2026-09-1\(i)T07:00:00Z")) }
    #expect(try store.listAll().count == 5)
    #expect(try store.listAll()[0].loggedAt == "2026-09-15T07:00:00Z")
}

@Test func pendingSyncIsOldestFirstAndOnlyUnconfirmedRows() throws {
    let store = DecisionLogStore(db: try AppDatabase.inMemory())
    let first = try store.append(entry(loggedAt: "2026-09-11T07:00:00Z"))
    try store.append(entry(loggedAt: "2026-09-12T07:00:00Z", choice: "N", recommendation: "MAINTAIN"))
    try store.append(entry(loggedAt: "2026-09-13T07:00:00Z"))
    try store.markSynced(localId: first, remoteLogId: 1)

    let pending = try store.pendingSync()
    #expect(pending.count == 2)
    #expect(pending.map(\.loggedAt) == ["2026-09-12T07:00:00Z", "2026-09-13T07:00:00Z"])
}

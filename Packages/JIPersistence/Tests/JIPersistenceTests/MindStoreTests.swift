import Foundation
import Testing
import CryptoKit
import GRDB
import JIVault
@testable import JIPersistence

/// In-memory `KeychainService` double so tests can unlock a real `VaultManager` (and therefore a
/// real `EnvelopeFieldCipher`, gated behind the `FieldCipher` protocol — `EnvelopeCodec`/
/// `EnvelopeFieldCipher` themselves are internal to `JIVault`) without touching the Keychain.
final class InMemoryKeychainService: KeychainService, @unchecked Sendable {
    private var key: SymmetricKey?
    func loadMasterKey() async throws -> SymmetricKey {
        guard let key else { throw KeychainError.itemNotFound }
        return key
    }
    func storeNewMasterKey() async throws -> SymmetricKey {
        let k = SymmetricKey(size: .bits256)
        key = k
        return k
    }
    func deleteMasterKey() async throws { key = nil }
}

func realCipher() async throws -> any FieldCipher {
    let manager = VaultManager(keychain: InMemoryKeychainService())
    return try await manager.unlock()
}

// MARK: - CheckInStore

@Test func checkInRoundTripsWithIdentityCipher() throws {
    let db = try AppDatabase.inMemory()
    let store = CheckInStore(db: db)
    let n = NewCheckIn(date: "2026-09-17", mood: .good, stress: 3, energy: 4, dosed: false, irritability: nil, restlessness: nil, appetite: nil, note: "fine day")
    try store.upsertToday(n)
    let fetched = try store.getByDate("2026-09-17")
    #expect(fetched?.mood == .good)
    #expect(fetched?.stress == 3)
    #expect(fetched?.energy == 4)
    #expect(fetched?.dosed == false)
    #expect(fetched?.note == "fine day")
}

@Test func checkInDosedTogglePersistsMicroAxes() throws {
    let db = try AppDatabase.inMemory()
    let store = CheckInStore(db: db)
    let n = NewCheckIn(date: "2026-09-17", mood: nil, stress: 2, energy: 2, dosed: true, irritability: 4, restlessness: 3, appetite: 2, note: nil)
    try store.upsertToday(n)
    let fetched = try store.getByDate("2026-09-17")
    #expect(fetched?.dosed == true)
    #expect(fetched?.irritability == 4)
    #expect(fetched?.restlessness == 3)
    #expect(fetched?.appetite == 2)
}

@Test func checkInUpsertUpdatesSameDateRowInPlace() throws {
    let db = try AppDatabase.inMemory()
    let store = CheckInStore(db: db)
    try store.upsertToday(NewCheckIn(date: "2026-09-17", mood: .okay, stress: 3, energy: 3, dosed: false, irritability: nil, restlessness: nil, appetite: nil, note: nil))
    try store.upsertToday(NewCheckIn(date: "2026-09-17", mood: .great, stress: 1, energy: 5, dosed: false, irritability: nil, restlessness: nil, appetite: nil, note: "updated"))
    let all = try store.listAll()
    #expect(all.count == 1)
    #expect(all.first?.mood == .great)
    #expect(all.first?.note == "updated")
}

@Test func checkInRoundTripsWithRealEnvelopeCipherAndCiphertextNeverEqualsPlaintext() async throws {
    let db = try AppDatabase.inMemory()
    let cipher = try await realCipher()
    let store = CheckInStore(db: db, cipher: cipher)
    try store.upsertToday(NewCheckIn(date: "2026-09-17", mood: .bad, stress: 5, energy: 1, dosed: true, irritability: 5, restlessness: 4, appetite: 1, note: "rough"))

    let fetched = try store.getByDate("2026-09-17")
    #expect(fetched?.mood == .bad)
    #expect(fetched?.note == "rough")

    let raw: (mood: String?, note: String?, stress: String?) = try await db.pool.read { conn in
        guard let row = try Row.fetchOne(conn, sql: "SELECT mood, note, stress FROM mind_checkin WHERE date = ?", arguments: ["2026-09-17"]) else {
            return (nil, nil, nil)
        }
        return (row["mood"], row["note"], row["stress"])
    }
    #expect(raw.mood != "bad")
    #expect(raw.note != "rough")
    #expect(raw.stress != "5")
}

@Test func isValidScoreAcceptsOnly1Through5() {
    #expect(isValidScore(1))
    #expect(isValidScore(5))
    #expect(!isValidScore(0))
    #expect(!isValidScore(6))
}

// MARK: - EventStore

@Test func eventRoundTripsWithIdentityCipher() throws {
    let db = try AppDatabase.inMemory()
    let store = EventStore(db: db)
    let id = try store.addEvent(NewMindEvent(date: "2026-09-17", timeLocal: "14:30", type: .migraine, severity: 4, prodrome: ["neck pull", "yawning"], triggers: "bright light", note: "aura"))
    let events = try store.recent(10)
    #expect(events.count == 1)
    #expect(events.first?.id == id)
    #expect(events.first?.type == .migraine)
    #expect(events.first?.severity == 4)
    #expect(events.first?.prodrome == ["neck pull", "yawning"])
    #expect(events.first?.triggers == "bright light")
    #expect(events.first?.note == "aura")
}

@Test func eventDeleteRemovesRow() throws {
    let db = try AppDatabase.inMemory()
    let store = EventStore(db: db)
    let id = try store.addEvent(NewMindEvent(date: "2026-09-17", timeLocal: "09:00", type: .reflux, severity: 2, prodrome: [], triggers: "", note: nil))
    try store.deleteEvent(id)
    #expect(try store.recent(10).isEmpty)
}

/// W4 exit criterion: raw `mind_event.type` column is an envelope.
@Test func eventTypeColumnIsAnEnvelopeUnderRealCipher() async throws {
    let db = try AppDatabase.inMemory()
    let cipher = try await realCipher()
    let store = EventStore(db: db, cipher: cipher)
    try store.addEvent(NewMindEvent(date: "2026-09-17", timeLocal: "14:30", type: .migraine, severity: 3, prodrome: [], triggers: "", note: nil))

    let rawType: String? = try await db.pool.read { conn in
        try Row.fetchOne(conn, sql: "SELECT type, severity FROM mind_event LIMIT 1")?["type"]
    }
    #expect(rawType != "migraine")
    #expect(rawType?.hasPrefix("jiv1:") == true)

    let events = try store.recent(1)
    #expect(events.first?.type == .migraine)
    #expect(events.first?.severity == 3)
}

@Test func eventTypeLabelsMatchOracleCopy() {
    #expect(eventTypeLabel(.migraine) == "Migraine")
    #expect(eventTypeLabel(.vomiting) == "Vomiting")
    #expect(eventTypeLabel(.reflux) == "Reflux")
    #expect(eventTypeLabel(.neck_pain) == "Neck pain")
    #expect(eventTypeLabel(.other) == "Other")
}

@Test func isValidSeverityAcceptsOnly1Through5() {
    #expect(isValidSeverity(1))
    #expect(isValidSeverity(5))
    #expect(!isValidSeverity(0))
    #expect(!isValidSeverity(6))
}

// MARK: - Who5Store

@Test func who5RoundTripsAndComputesRawAndPct() throws {
    let db = try AppDatabase.inMemory()
    let store = Who5Store(db: db)
    let id = try store.add(NewWho5(date: "2026-09-17", items: [4, 3, 2, 5, 1]))
    let latest = try store.latest()
    #expect(latest?.id == id)
    #expect(latest?.items == [4, 3, 2, 5, 1])
    #expect(latest?.raw == 15)
    #expect(latest?.pct == 60)
}

@Test func who5AddRejectsWrongItemCountOrOutOfRangeResponse() throws {
    let db = try AppDatabase.inMemory()
    let store = Who5Store(db: db)
    #expect(throws: Who5Error.invalidItems) { try store.add(NewWho5(date: "2026-09-17", items: [1, 2, 3])) }
    #expect(throws: Who5Error.invalidItems) { try store.add(NewWho5(date: "2026-09-17", items: [1, 2, 3, 4, 6])) }
}

@Test func who5RoundTripsWithRealEnvelopeCipher() async throws {
    let db = try AppDatabase.inMemory()
    let cipher = try await realCipher()
    let store = Who5Store(db: db, cipher: cipher)
    try store.add(NewWho5(date: "2026-09-17", items: [0, 0, 0, 0, 0]))
    let latest = try store.latest()
    #expect(latest?.raw == 0)
    #expect(latest?.pct == 0)

    let rawRaw: String? = try await db.pool.read { conn in
        try Row.fetchOne(conn, sql: "SELECT i1, raw, pct FROM mind_who5 LIMIT 1")?["raw"]
    }
    #expect(rawRaw != "0")
}

@Test func who5RawSumsFiveItems() {
    #expect(who5Raw([5, 5, 5, 5, 5]) == 25)
    #expect(who5Raw([0, 0, 0, 0, 0]) == 0)
}

@Test func who5PercentIsRawTimesFour() {
    #expect(who5Percent(25) == 100)
    #expect(who5Percent(12) == 48)
    #expect(who5Percent(0) == 0)
}

@Test func isValidResponseAcceptsOnly0Through5() {
    #expect(isValidResponse(0))
    #expect(isValidResponse(5))
    #expect(!isValidResponse(-1))
    #expect(!isValidResponse(6))
}

@Test func who5DueThisWeekIsTrueWhenNoEntryEverRecorded() {
    #expect(who5DueThisWeek(nil, now: Date()))
}

@Test func who5DueThisWeekIsFalseForADateInsideTheSameIsoWeek() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    // 2026-09-17 is a Thursday; 2026-09-14 (Monday) is in the same ISO week.
    let thursday = cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!
    #expect(who5DueThisWeek("2026-09-14", now: thursday, calendar: cal) == false)
}

@Test func who5DueThisWeekIsTrueForADateInAnEarlierWeek() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let thursday = cal.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!
    #expect(who5DueThisWeek("2026-09-07", now: thursday, calendar: cal))
}

import Foundation
import Testing
import JICore
@testable import JIPersistence

private struct Payload: Codable, Equatable { var weightKg: Double; var date: String? }

@Test func outboxEnqueueIsPendingBeforeAnyNetworkAttempt() throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let id = try outbox.enqueue(kind: "weighin", payload: Payload(weightKg: 82.5, date: "2026-09-17"))
    let rows = try outbox.pending()
    #expect(rows.count == 1)
    #expect(rows[0].id == id)
    #expect(rows[0].kind == "weighin")
    #expect(rows[0].attempts == 0)
    #expect(rows[0].lastError == nil)
}

@Test func outboxMarkFailedBumpsAttemptsAndRecordsError() throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let id = try outbox.enqueue(kind: "weighin", payload: Payload(weightKg: 82.5, date: nil))
    try outbox.markFailed(id: id, error: "Garmin FIT upload rejected")
    let rows = try outbox.pending()
    #expect(rows.count == 1)
    #expect(rows[0].attempts == 1)
    #expect(rows[0].lastError == "Garmin FIT upload rejected")

    try outbox.markFailed(id: id, error: "still offline")
    #expect(try outbox.pending()[0].attempts == 2)
    #expect(try outbox.pending()[0].lastError == "still offline")
}

@Test func outboxMarkSentRetiresTheRow() throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let id = try outbox.enqueue(kind: "weighin", payload: Payload(weightKg: 82.5, date: nil))
    try outbox.markSent(id: id)
    #expect(try outbox.pending().isEmpty)
}

@Test func outboxRoundTripsPayloadJSON() throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    _ = try outbox.enqueue(kind: "weighin", payload: Payload(weightKg: 82.5, date: "2026-09-17"))
    let row = try #require(try outbox.pending().first)
    let decoded = try JSON.decoder.decode(Payload.self, from: row.payload)
    #expect(decoded == Payload(weightKg: 82.5, date: "2026-09-17"))
}

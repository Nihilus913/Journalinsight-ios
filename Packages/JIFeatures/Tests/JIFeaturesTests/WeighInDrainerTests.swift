import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// `WeighInProviding` double — mirrors `TrainingFakeProvider`'s "can be told to fail" shape,
/// scoped to this lane's own protocol.
nonisolated final class WeighInFakeProvider: WeighInProviding, @unchecked Sendable {
    var error: HubError?
    var result: (Double, String?) -> WeighinResult = { weightKg, date in
        WeighinResult(status: "ok", weightKg: weightKg, date: date ?? "2026-09-17", garminConfirmed: true)
    }

    func logWeighin(weightKg: Double, date: String?) async throws -> WeighinResult {
        if let error { throw error }
        return result(weightKg, date)
    }
}

@Test func drainOnceMarksSentOnSuccess() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let provider = WeighInFakeProvider()
    let drainer = await OutboxDrainer(outbox: outbox, provider: provider)
    let id = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 82.5, date: "2026-09-17"))

    let results = await drainer.drainOnce()

    guard case .success(let result) = results[id] else { Issue.record("expected success"); return }
    #expect(result.weightKg == 82.5)
    #expect(try outbox.pending().isEmpty) // sent rows are retired
}

@Test func drainOnceLeavesRowPendingOnNetworkFailureAndRecordsError() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let provider = WeighInFakeProvider()
    provider.error = .network("offline")
    let drainer = await OutboxDrainer(outbox: outbox, provider: provider)
    let id = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 82.5, date: nil))

    let results = await drainer.drainOnce()

    guard case .failure = results[id] else { Issue.record("expected failure"); return }
    let rows = try outbox.pending()
    #expect(rows.count == 1) // still pending — offline, not delivered
    #expect(rows[0].attempts == 1)
    #expect(rows[0].lastError == "offline")
}

@Test func drainOnceRecordsHubDetailVerbatimOn502() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let provider = WeighInFakeProvider()
    provider.error = .yazioAuthExpired(detail: "Garmin FIT upload rejected")
    let drainer = await OutboxDrainer(outbox: outbox, provider: provider)
    let id = try outbox.enqueue(kind: OutboxDrainer.weighInKind, payload: WeighinBody(weightKg: 82.5, date: nil))

    _ = await drainer.drainOnce()

    let rows = try outbox.pending()
    #expect(rows[0].id == id)
    #expect(rows[0].attempts == 1)
    #expect(rows[0].lastError == "Garmin FIT upload rejected") // hub `detail`, verbatim
}

@Test func drainOnceIgnoresRowsOfAnotherKind() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let provider = WeighInFakeProvider()
    let drainer = await OutboxDrainer(outbox: outbox, provider: provider)
    _ = try outbox.enqueue(kind: "some_other_write", payload: ["x": 1])

    let results = await drainer.drainOnce()

    #expect(results.isEmpty)
    #expect(try outbox.pending().count == 1) // untouched
}

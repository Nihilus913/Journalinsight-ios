import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// B-44 Option B: the phone's morning verdict is queued in the `Outbox` (kind `ondevice_verdict`)
/// and replayed by `OutboxDrainer` — offline-first, newest row of a day wins, a 404 (a hub that
/// predates the route) keeps it queued.
private final class FakeUploader: OnDeviceVerdictUploading, @unchecked Sendable {   // @unchecked: test-only, one task
    var sent: [OnDeviceVerdictUpload] = []
    var error: (any Error)?
    func uploadOnDeviceVerdict(_ body: OnDeviceVerdictUpload) async throws -> OnDeviceVerdictStored {
        if let error { throw error }
        sent.append(body)
        return OnDeviceVerdictStored(date: body.date, verdict: body.verdict, hubVerdict: nil, receivedAt: "2026-10-05T05:03:00Z")
    }
}

private func upload(_ day: String, _ verdict: String) -> OnDeviceVerdictUpload {
    OnDeviceVerdictUpload(date: day, verdict: verdict, reason: nil, sessionPrescription: nil, baselineNights: 2,
                          inputsDigest: "d", computedAt: "2026-10-05T05:02:00Z")
}

@Test @MainActor func onDeviceVerdictRowIsDeliveredAndRetired() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let fake = FakeUploader()
    _ = try outbox.enqueue(kind: OnDeviceVerdictUpload.outboxKind, payload: upload("2026-10-05", "GO — Day 2"))
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, onDeviceVerdict: fake)
    #expect(drainer.drainableKinds.contains(OutboxDrainer.onDeviceVerdictKind))
    let results = await drainer.drainOnce()
    #expect(fake.sent.map(\.verdict) == ["GO — Day 2"])
    #expect(try outbox.pending().isEmpty)
    if case .success(.onDeviceVerdict(let stored))? = results.values.first { #expect(stored.date == "2026-10-05") } else { Issue.record("no delivery") }
}

@Test @MainActor func onlyTheNewestRowOfADayIsSent() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let fake = FakeUploader()
    _ = try outbox.enqueue(kind: OnDeviceVerdictUpload.outboxKind, payload: upload("2026-10-05", "GO — Day 2"))
    _ = try outbox.enqueue(kind: OnDeviceVerdictUpload.outboxKind, payload: upload("2026-10-05", "REST — recovery"))
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, onDeviceVerdict: fake).drainOnce()
    #expect(fake.sent.map(\.verdict) == ["REST — recovery"])
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func offlineAndMissingRouteKeepTheRowQueued() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let fake = FakeUploader()
    _ = try outbox.enqueue(kind: OnDeviceVerdictUpload.outboxKind, payload: upload("2026-10-05", "GO — Day 2"))
    fake.error = HubError.http(status: 404, detail: "Not Found")
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, onDeviceVerdict: fake).drainOnce()
    #expect(try outbox.pending().count == 1)
    fake.error = URLError(.notConnectedToInternet)
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, onDeviceVerdict: fake).drainOnce()
    #expect(try outbox.pending().count == 1)
    fake.error = nil
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, onDeviceVerdict: fake).drainOnce()
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func aDrainerWithoutTheUploaderLeavesTheRowAlone() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    _ = try outbox.enqueue(kind: OnDeviceVerdictUpload.outboxKind, payload: upload("2026-10-05", "GO — Day 2"))
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil).drainOnce()
    #expect(try outbox.pending().count == 1)
}

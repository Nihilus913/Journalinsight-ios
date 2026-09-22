import Testing
import Foundation
import JICore
import JIPersistence
@testable import JIFeatures

@Suite struct DecideViewTests {
    @Test func decideDisablesGoWhileSyncing() {
        let a = decideActions(verdict: verdictParts(nil), syncing: true)
        #expect(a.go == false && a.adjust == false)
    }
    @Test func goAndAdjustOnTrainingDay() {
        let a = decideActions(verdict: verdictParts("GO — Full Upper"), syncing: false)
        #expect(a.go && a.adjust)
    }
    @Test func restDayGoOnly() {
        let a = decideActions(verdict: verdictParts("REST"), syncing: false)
        #expect(a.go && !a.adjust)
    }
    /// Pinned outcome (GateRespondCard.swift `respond`): a non-network hub rejection (HTTP 500)
    /// lands in `.failed`, clears `choice` → `responded == false`, and surfaces `errorMessage`.
    /// Decide advances only on `responded`, so it stays put and shows the error.
    @Test @MainActor func decideStaysOnFailedRespond() async throws {
        let provider = GateRespondFakeProvider(); provider.error = .http(status: 500, detail: "boom")
        let db = try AppDatabase.inMemory()
        let m = GateRespondViewModel(recommendation: .maintain, provider: provider, outbox: Outbox(db: db), decisionLog: DecisionLogStore(db: db))
        _ = await m.respond(choice: .yes)
        #expect(m.responded == false)
        #expect(m.errorMessage != nil)
        if case .failed = m.phase {} else { Issue.record("expected .failed, got \(m.phase)") }
    }
    /// Offline (network error) queues to the Outbox → `.queued`, `responded == true` → Decide advances.
    @Test @MainActor func decideAdvancesOnQueuedRespond() async throws {
        let provider = GateRespondFakeProvider(); provider.error = .network("offline")
        let db = try AppDatabase.inMemory()
        let m = GateRespondViewModel(recommendation: .maintain, provider: provider, outbox: Outbox(db: db), decisionLog: DecisionLogStore(db: db))
        _ = await m.respond(choice: .yes)
        #expect(m.phase == .queued)
        #expect(m.responded)
    }
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W5b-L4 (P-gate-respond) — the card's pinned order: outbox row FIRST, then the POST, then the
/// `decision_log_mirror` row. Ports the observable contract of the RN oracle's
/// `mobile/__tests__/gateActions.test.tsx` (provider called with the right payload; a settled
/// status on success; the error surfaced on rejection) onto the Swift offline-first shape.

nonisolated final class GateRespondFakeProvider: GateRespondProviding, @unchecked Sendable { // @unchecked: test double mutated only before the call under test
    var error: HubError?
    var respondResult = GateRespondResult(pdfRequested: true, logId: 5)
    var feelResult = FeelResult(feelId: 9)
    var respondCalls: [(GateChoice, String, Int)] = []
    var feelCalls: [(Int, String, String?)] = []
    /// When set, the provider observes the outbox at call time — proves "enqueue FIRST".
    var onRespond: (() -> Void)?

    func respondGate(choice: GateChoice, overrideReason: String, windowDays: Int) async throws -> GateRespondResult {
        respondCalls.append((choice, overrideReason, windowDays))
        onRespond?()
        if let error { throw error }
        return respondResult
    }

    func logFeel(feelScore: Int, notes: String, date: String?) async throws -> FeelResult {
        feelCalls.append((feelScore, notes, date))
        if let error { throw error }
        return feelResult
    }
}

@MainActor
private func makeVM(
    recommendation: GateRecommendation = .progress,
    provider: GateRespondFakeProvider = GateRespondFakeProvider()
) throws -> (GateRespondViewModel, Outbox, DecisionLogStore) {
    let db = try AppDatabase.inMemory()
    let outbox = Outbox(db: db)
    let log = DecisionLogStore(db: db)
    let fixedNow = Date(timeIntervalSince1970: 1_789_000_000) // 2026-09-10T00:26:40Z
    let vm = GateRespondViewModel(
        recommendation: recommendation, windowDays: 7, provider: provider,
        outbox: outbox, decisionLog: log, now: { fixedNow }
    )
    return (vm, outbox, log)
}

// MARK: - respond

@Test @MainActor func respondEnqueuesTheOutboxRowBeforeThePost() async throws {
    let provider = GateRespondFakeProvider()
    let (vm, outbox, _) = try makeVM(provider: provider)
    nonisolated(unsafe) var pendingAtPostTime: [OutboxRow] = []
    provider.onRespond = { pendingAtPostTime = (try? outbox.pending()) ?? [] }

    await vm.respond(choice: .yes)

    #expect(pendingAtPostTime.count == 1)
    #expect(pendingAtPostTime.first?.kind == GateRespondViewModel.gateRespondKind)
    let body = try JSONDecoder().decode(GateRespondBody.self, from: pendingAtPostTime[0].payload)
    #expect(body == GateRespondBody(choice: .yes, overrideReason: "", windowDays: 7))
}

@Test @MainActor func respondSuccessRetiresTheOutboxRowAndWritesASyncedMirrorRow() async throws {
    let provider = GateRespondFakeProvider()
    provider.respondResult = GateRespondResult(pdfRequested: true, logId: 41)
    let (vm, outbox, log) = try makeVM(recommendation: .maintain, provider: provider)

    let ok = await vm.respond(choice: .override, overrideReason: "sore shoulder")

    #expect(ok)
    #expect(vm.phase == .logged)
    #expect(vm.responded)
    #expect(vm.choice == .override)
    #expect(vm.pdfRequested)
    #expect(provider.respondCalls.count == 1)
    #expect(provider.respondCalls[0].0 == .override)
    #expect(provider.respondCalls[0].1 == "sore shoulder")
    #expect(provider.respondCalls[0].2 == 7)
    #expect(try outbox.pending().isEmpty)

    let rows = try log.recent(limit: 10)
    #expect(rows.count == 1)
    #expect(rows[0].recommendation == "MAINTAIN")
    #expect(rows[0].userChoice == "override")
    #expect(rows[0].overrideReason == "sore shoulder")
    #expect(rows[0].windowDays == 7)
    #expect(rows[0].remoteLogId == 41)
    #expect(rows[0].synced)
    #expect(rows[0].loggedAt == "2026-09-10T00:26:40Z")
    #expect(try log.pendingSync().isEmpty)
}

@Test @MainActor func respondSkipWritesNoOverrideReason() async throws {
    let (vm, _, log) = try makeVM()
    await vm.respond(choice: .skip)
    let row = try log.recent(limit: 1)[0]
    #expect(row.userChoice == "N")
    #expect(row.overrideReason == nil)
}

@Test @MainActor func respondOfflineLeavesTheOutboxRowPendingAndNoMirrorRow() async throws {
    let provider = GateRespondFakeProvider()
    provider.error = .network("offline")
    let (vm, outbox, log) = try makeVM(provider: provider)

    let ok = await vm.respond(choice: .yes)

    #expect(ok) // queued is not a user-facing failure
    #expect(vm.phase == .queued)
    #expect(vm.responded)
    #expect(vm.choice == .yes)
    let pending = try outbox.pending()
    #expect(pending.count == 1)
    #expect(pending[0].attempts == 1)
    #expect(pending[0].lastError == "offline")
    #expect(try log.recent(limit: 10).isEmpty) // only a confirmed POST writes the mirror row
}

@Test @MainActor func respond502BumpsAttemptsAndSurfacesTheHubDetailVerbatim() async throws {
    let provider = GateRespondFakeProvider()
    provider.error = .yazioAuthExpired(detail: "hub database is down")
    let (vm, outbox, log) = try makeVM(provider: provider)

    let ok = await vm.respond(choice: .yes)

    #expect(!ok)
    #expect(vm.phase == .failed("hub database is down"))
    #expect(vm.errorMessage == "hub database is down")
    #expect(!vm.responded)
    #expect(vm.choice == nil) // oracle onError: rolls the optimistic choice back
    let pending = try outbox.pending()
    #expect(pending.count == 1)
    #expect(pending[0].attempts == 1)
    #expect(pending[0].lastError == "hub database is down")
    #expect(try log.recent(limit: 10).isEmpty)
}

@Test @MainActor func respondUnauthorizedUsesTheNamedCopy() async throws {
    let provider = GateRespondFakeProvider()
    provider.error = .unauthorized
    let (vm, _, _) = try makeVM(provider: provider)
    await vm.respond(choice: .yes)
    #expect(vm.errorMessage == "Hub rejected the token — check Settings › Connection.")
}

@Test @MainActor func undoClearsLocalStateOnlyAndKeepsTheMirrorRow() async throws {
    let (vm, _, log) = try makeVM()
    await vm.respond(choice: .yes)
    #expect(vm.responded)

    vm.undo()

    #expect(!vm.responded)
    #expect(vm.choice == nil)
    #expect(vm.phase == .idle)
    #expect(try log.recent(limit: 10).count == 1) // what the user did stays recorded
}

// MARK: - feel

@Test @MainActor func logFeelEnqueuesFirstThenConfirms() async throws {
    let provider = GateRespondFakeProvider()
    let (vm, outbox, _) = try makeVM(provider: provider)

    let ok = await vm.logFeel(score: 4, notes: "legs heavy", date: "2026-09-18")

    #expect(ok)
    #expect(vm.feelPhase == .logged)
    #expect(vm.feelScore == 4)
    #expect(provider.feelCalls.count == 1)
    #expect(provider.feelCalls[0].0 == 4)
    #expect(provider.feelCalls[0].1 == "legs heavy")
    #expect(provider.feelCalls[0].2 == "2026-09-18")
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func logFeelOfflineLeavesThePayloadPending() async throws {
    let provider = GateRespondFakeProvider()
    provider.error = .network("offline")
    let (vm, outbox, _) = try makeVM(provider: provider)

    let ok = await vm.logFeel(score: 3)

    #expect(ok)
    #expect(vm.feelPhase == .queued)
    let pending = try outbox.pending()
    #expect(pending.count == 1)
    #expect(pending[0].kind == GateRespondViewModel.sessionFeelKind)
    #expect(pending[0].attempts == 1)
    let body = try JSONDecoder().decode(FeelBody.self, from: pending[0].payload)
    #expect(body == FeelBody(feelScore: 3, notes: "", date: nil))
}

@Test @MainActor func logFeel422BumpsAttemptsAndSurfacesDetailVerbatim() async throws {
    let provider = GateRespondFakeProvider()
    provider.error = .http(status: 422, detail: "feel_score must be 1-5")
    let (vm, outbox, _) = try makeVM(provider: provider)

    let ok = await vm.logFeel(score: 9)

    #expect(!ok)
    #expect(vm.feelPhase == .failed("feel_score must be 1-5"))
    #expect(vm.feelScore == nil) // oracle onError: rolls back to no-selection
    #expect(try outbox.pending()[0].attempts == 1)
    #expect(try outbox.pending()[0].lastError == "feel_score must be 1-5")
}

// MARK: - copy / section helpers

@Test func choiceLabelsMatchTheOracle() {
    #expect(GateRespondCopy.choiceLabels[.yes] == "generate plan")
    #expect(GateRespondCopy.choiceLabels[.skip] == "skip")
    #expect(GateRespondCopy.choiceLabels[.override] == "override & generate")
    #expect(GateRespondCopy.overrideReasons == ["Feel good despite metrics", "Experiment protocol", "Schedule constraint", "Clinician guidance", "Other…"])
}

@Test func decisionLogSectionLabelsAndTimestampMatchTheOracle() {
    #expect(DecisionLogSection.choiceLabels["y"] == "Generated plan")
    #expect(DecisionLogSection.choiceLabels["N"] == "Skipped")
    #expect(DecisionLogSection.choiceLabels["override"] == "Overrode")
    #expect(DecisionLogSection.timestamp("2026-09-01T08:00:00.000Z") == "2026-09-01 08:00")
}

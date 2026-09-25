import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-B57b L1 — `effectiveVerdict`, `VerdictOverrideViewModel` (Outbox-first, like
// `GateRespondViewModel.respond`) and the drainer's `verdictOverride` kinds.

nonisolated final class VerdictOverrideFakeProvider: VerdictOverrideProviding, @unchecked Sendable { // @unchecked: test double mutated only before the call under test
    var error: HubError?
    var clearError: HubError?
    var setCalls: [(String, VerdictOverrideChoice, String)] = []
    var clearCalls: [String] = []
    var onSet: (() -> Void)?
    var onClear: (() -> Void)?

    func setVerdictOverride(date: String, choice: VerdictOverrideChoice, reason: String) async throws -> VerdictOverride {
        setCalls.append((date, choice, reason))
        onSet?()
        if let error { throw error }
        return VerdictOverride(date: date, choice: choice, reason: reason.isEmpty ? nil : reason,
                               session: "hub:\(choice.rawValue)", createdAt: "2026-09-23T06:00:00+02:00")
    }

    func clearVerdictOverride(date: String) async throws {
        clearCalls.append(date)
        onClear?()
        if let clearError { throw clearError }
    }
}

@MainActor
private func makeVM(provider: VerdictOverrideFakeProvider = VerdictOverrideFakeProvider(),
                    current: VerdictOverride? = nil) throws -> (VerdictOverrideViewModel, Outbox) {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let vm = VerdictOverrideViewModel(provider: provider, outbox: outbox, current: current,
                                      now: { Date(timeIntervalSince1970: 1_790_000_000) })
    return (vm, outbox)
}

private let modifiedParts = verdictParts("MODIFIED (HRV low) — Easy Z2 30–40 min")

// MARK: - effectiveVerdict

@Test func effectiveVerdictWithoutOverrideIsTheVerdict() {
    let e = effectiveVerdict(parts: modifiedParts, override: nil)
    #expect(e.word == "MODIFIED (HRV low)")
    #expect(e.session == "Easy Z2 30–40 min")
    #expect(e.wasCaption == nil)
    #expect(effectiveVerdictTone(parts: modifiedParts, override: nil) == .amber)
}

@Test func effectiveVerdictFullOnModifiedMatchesTheCardExample() {
    let o = VerdictOverride(date: "2026-09-23", choice: .full, reason: "Feel good despite metrics", session: "Full Upper")
    let e = effectiveVerdict(parts: verdictParts("MODIFIED — Easy Z2 30–40 min"), override: o)
    #expect(e.word == "FULL")
    #expect(e.session == "Full Upper")
    #expect(e.wasCaption == "was Modified · Feel good despite metrics")
    #expect(effectiveVerdictTone(parts: modifiedParts, override: o) == .go)
}

@Test func effectiveVerdictCaptionStripsTheParentheticalAndOmitsAnEmptyReason() {
    let o = VerdictOverride(date: "2026-09-23", choice: .rest, reason: nil, session: "Rest — walks only")
    let e = effectiveVerdict(parts: modifiedParts, override: o)
    #expect(e.word == "REST")
    #expect(e.session == "Rest — walks only")
    #expect(e.wasCaption == "was Modified")
    #expect(effectiveVerdictTone(parts: modifiedParts, override: o) == .muted)
}

@Test func effectiveVerdictAcceptKeepsTheVerdictWithNoCaption() {
    let o = VerdictOverride(date: "2026-09-23", choice: .accept, reason: nil, session: "Easy Z2 30–40 min")
    let e = effectiveVerdict(parts: modifiedParts, override: o)
    #expect(e.word == "MODIFIED (HRV low)")
    #expect(e.session == "Easy Z2 30–40 min")
    #expect(e.wasCaption == nil)
    #expect(effectiveVerdictTone(parts: modifiedParts, override: o) == .amber)
}

@Test func effectiveVerdictModifiedOnAModifiedVerdictIsNotAChange() {
    let o = VerdictOverride(date: "2026-09-23", choice: .modified, reason: "Schedule constraint", session: "Easy Z2 30–40 min")
    let e = effectiveVerdict(parts: modifiedParts, override: o)
    #expect(e.word == "MODIFIED")
    #expect(e.wasCaption == nil)
}

@Test func effectiveVerdictModifiedOnGoCaptionsTheChange() {
    let go = verdictParts("GO — Full Upper")
    let o = VerdictOverride(date: "2026-09-23", choice: .modified, reason: "Schedule constraint", session: "Easy Z2 30–40 min")
    let e = effectiveVerdict(parts: go, override: o)
    #expect(e.word == "MODIFIED")
    #expect(e.session == "Easy Z2 30–40 min")
    #expect(e.wasCaption == "was Full · Schedule constraint")
}

@Test func effectiveVerdictWithoutAVerdictCaptionsOnlyTheReason() {
    let none = verdictParts(nil)
    let o = VerdictOverride(date: "2026-09-23", choice: .full, reason: "Experiment protocol", session: "Full Upper")
    let e = effectiveVerdict(parts: none, override: o)
    #expect(e.word == "FULL")
    #expect(e.wasCaption == "Experiment protocol")
}

@Test func effectiveVerdictFallsBackToALocalSessionWhenTheOverrideHasNone() {
    let o = VerdictOverride(date: "2026-09-23", choice: .rest, reason: nil, session: "")
    #expect(effectiveVerdict(parts: modifiedParts, override: o).session == "Rest — walks only")
}

@Test func localOverrideSessionMirrorsTheHubResolution() {
    let go = verdictParts("GO — Full Upper")
    #expect(localOverrideSession(choice: .accept, parts: modifiedParts, sessionForToday: "Full Upper") == "Easy Z2 30–40 min")
    #expect(localOverrideSession(choice: .full, parts: modifiedParts, sessionForToday: "Full Upper") == "Full Upper")
    #expect(localOverrideSession(choice: .full, parts: go, sessionForToday: nil) == "Full Upper")
    #expect(localOverrideSession(choice: .modified, parts: modifiedParts, sessionForToday: nil) == "Easy Z2 30–40 min")
    #expect(localOverrideSession(choice: .modified, parts: verdictParts("REDUCED — Upper light 3×8"), sessionForToday: nil) == "Upper light 3×8")
    #expect(localOverrideSession(choice: .modified, parts: go, sessionForToday: nil) == "Easy Z2 30–40 min")
    #expect(localOverrideSession(choice: .rest, parts: go, sessionForToday: nil) == "Rest — walks only")
}

// MARK: - VerdictOverrideViewModel

@Test @MainActor func setOverrideEnqueuesTheOutboxRowBeforeThePost() async throws {
    let provider = VerdictOverrideFakeProvider()
    let (vm, outbox) = try makeVM(provider: provider)
    nonisolated(unsafe) var pendingAtPost: [OutboxRow] = []
    provider.onSet = { pendingAtPost = (try? outbox.pending()) ?? [] }

    await vm.setOverride(date: "2026-09-23", choice: .full, reason: "Feel good despite metrics")

    #expect(pendingAtPost.count == 1)
    #expect(pendingAtPost.first?.kind == VerdictOverrideViewModel.verdictOverrideKind)
    #expect(try JSONDecoder().decode(VerdictOverrideBody.self, from: pendingAtPost[0].payload)
            == VerdictOverrideBody(date: "2026-09-23", choice: .full, reason: "Feel good despite metrics"))
}

@Test @MainActor func setOverrideSuccessMirrorsTheHubRowAndRetiresTheOutboxRow() async throws {
    let provider = VerdictOverrideFakeProvider()
    let (vm, outbox) = try makeVM(provider: provider)

    let ok = await vm.setOverride(date: "2026-09-23", choice: .rest, reason: "")

    #expect(ok)
    #expect(vm.phase == .logged)
    #expect(vm.settled)
    #expect(vm.errorMessage == nil)
    #expect(vm.current?.session == "hub:rest")
    #expect(vm.current?.createdAt != nil)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func setOverrideOfflineIsQueuedWithAnOptimisticOverride() async throws {
    let provider = VerdictOverrideFakeProvider()
    provider.error = .network("offline")
    let (vm, outbox) = try makeVM(provider: provider)

    let ok = await vm.setOverride(date: "2026-09-23", choice: .full, reason: "Experiment protocol", optimisticSession: "Full Upper")

    #expect(ok)
    #expect(vm.phase == .queued)
    #expect(vm.settled)
    #expect(vm.current == VerdictOverride(date: "2026-09-23", choice: .full, reason: "Experiment protocol", session: "Full Upper", createdAt: nil))
    let rows = try outbox.pending()
    #expect(rows.count == 1 && rows[0].attempts == 1)
}

@Test @MainActor func setOverrideRejectionFailsAndKeepsThePreviousOverride() async throws {
    let prior = VerdictOverride(date: "2026-09-23", choice: .accept, reason: nil, session: "Easy Z2 30–40 min")
    let provider = VerdictOverrideFakeProvider()
    provider.error = .http(status: 422, detail: "choice must be one of accept/full/modified/rest")
    let (vm, _) = try makeVM(provider: provider, current: prior)

    let ok = await vm.setOverride(date: "2026-09-23", choice: .full)

    #expect(!ok)
    #expect(!vm.settled)
    #expect(vm.phase == .failed("choice must be one of accept/full/modified/rest"))
    #expect(vm.errorMessage == "choice must be one of accept/full/modified/rest")
    #expect(vm.current == prior)
}

@Test @MainActor func aNewerOverrideRetiresAnOlderQueuedOneForTheSameDate() async throws {
    let provider = VerdictOverrideFakeProvider()
    provider.error = .network("offline")
    let (vm, outbox) = try makeVM(provider: provider)
    await vm.setOverride(date: "2026-09-23", choice: .rest)
    _ = try outbox.enqueue(kind: VerdictOverrideViewModel.verdictOverrideKind, payload: VerdictOverrideBody(date: "2026-09-22", choice: .full))

    await vm.setOverride(date: "2026-09-23", choice: .full)

    let bodies = try outbox.pending().map { try JSONDecoder().decode(VerdictOverrideBody.self, from: $0.payload) }
    #expect(bodies.map(\.choice) == [.full, .full])
    #expect(bodies.map(\.date).sorted() == ["2026-09-22", "2026-09-23"])
}

@Test @MainActor func clearDeletesAndDropsTheCurrentOverride() async throws {
    let provider = VerdictOverrideFakeProvider()
    let (vm, outbox) = try makeVM(provider: provider, current: VerdictOverride(date: "2026-09-23", choice: .rest, reason: nil, session: "Rest — walks only"))
    nonisolated(unsafe) var kindsAtDelete: [String] = []
    provider.onClear = { kindsAtDelete = ((try? outbox.pending()) ?? []).map(\.kind) }

    let ok = await vm.clear(date: "2026-09-23")

    #expect(ok)
    #expect(kindsAtDelete == [VerdictOverrideViewModel.verdictOverrideClearKind])
    #expect(provider.clearCalls == ["2026-09-23"])
    #expect(vm.current == nil)
    #expect(vm.phase == .idle)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func clearRetiresAQueuedSetForThatDateSoItNeverReplays() async throws {
    let provider = VerdictOverrideFakeProvider()
    provider.error = .network("offline")
    provider.clearError = .network("offline")
    let (vm, outbox) = try makeVM(provider: provider)
    await vm.setOverride(date: "2026-09-23", choice: .rest)

    let ok = await vm.clear(date: "2026-09-23")

    #expect(ok)
    #expect(vm.current == nil)
    #expect(try outbox.pending().map(\.kind) == [VerdictOverrideViewModel.verdictOverrideClearKind])
}

@Test @MainActor func clearTreatsA404AsAlreadyCleared() async throws {
    let provider = VerdictOverrideFakeProvider()
    provider.clearError = .http(status: 404, detail: "no override")
    let (vm, outbox) = try makeVM(provider: provider)
    #expect(await vm.clear(date: "2026-09-23"))
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func clearRejectionFailsAndKeepsTheOverride() async throws {
    let prior = VerdictOverride(date: "2026-09-23", choice: .rest, reason: nil, session: "Rest — walks only")
    let provider = VerdictOverrideFakeProvider()
    provider.clearError = .unauthorized
    let (vm, _) = try makeVM(provider: provider, current: prior)
    #expect(await vm.clear(date: "2026-09-23") == false)
    #expect(vm.current == prior)
    #expect(vm.errorMessage == "Hub rejected the token — check Settings › Connection.")
}

// MARK: - OutboxDrainer

@Test @MainActor func drainerKnowsAndDeliversVerdictOverrideRows() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let provider = VerdictOverrideFakeProvider()
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, verdictOverride: provider)
    #expect(OutboxDrainer.knownKinds.isSuperset(of: [OutboxDrainer.verdictOverrideKind, OutboxDrainer.verdictOverrideClearKind]))
    #expect(drainer.drainableKinds == [OutboxDrainer.verdictOverrideKind, OutboxDrainer.verdictOverrideClearKind])
    let s = try outbox.enqueue(kind: OutboxDrainer.verdictOverrideKind, payload: VerdictOverrideBody(date: "2026-09-23", choice: .modified, reason: "Schedule constraint"))
    let c = try outbox.enqueue(kind: OutboxDrainer.verdictOverrideClearKind, payload: VerdictOverrideClearBody(date: "2026-09-22"))

    let results = await drainer.drainOnce()

    guard case .success(.verdictOverride(let o)) = results[s] else { Issue.record("expected override success"); return }
    #expect(o.choice == .modified)
    guard case .success(.verdictOverrideCleared) = results[c] else { Issue.record("expected clear success"); return }
    #expect(provider.setCalls.count == 1 && provider.setCalls[0].2 == "Schedule constraint")
    #expect(provider.clearCalls == ["2026-09-22"])
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func hubConvenienceInitPicksUpVerdictOverrideProviding() throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let drainer = OutboxDrainer(outbox: outbox, hub: VerdictOverrideFakeProvider())
    #expect(drainer.drainableKinds == [OutboxDrainer.verdictOverrideKind, OutboxDrainer.verdictOverrideClearKind])
}

@Test @MainActor func drainerLeavesVerdictOverrideRowsPendingWithoutAProvider() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil)
    _ = try outbox.enqueue(kind: OutboxDrainer.verdictOverrideKind, payload: VerdictOverrideBody(date: "2026-09-23", choice: .rest))
    #expect(await drainer.drainOnce().isEmpty)
    #expect(try outbox.pending().count == 1)
}

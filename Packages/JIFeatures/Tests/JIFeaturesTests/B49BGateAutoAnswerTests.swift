import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-B49B G-3: the hub's automatic gate answer shows as "Answered automatically · <FULL/GATED>
// from <workout>" on the Today line; the manual controls stay as the override.

@MainActor
private func makeVM(provider: GateRespondFakeProvider = GateRespondFakeProvider()) throws -> GateRespondViewModel {
    let db = try AppDatabase.inMemory()
    return GateRespondViewModel(recommendation: .progress, windowDays: 7, provider: provider,
                                outbox: Outbox(db: db), decisionLog: DecisionLogStore(db: db),
                                now: { Date(timeIntervalSince1970: 1_789_000_000) })
}

private let autoGated = GateAnswer(logId: 12, date: "2026-09-29", choice: "N", source: "auto", classification: "GATED", workout: "Easy Run")

@Test @MainActor func seedingAnAutomaticAnswerShowsItAsAnsweredWithTheAutoLine() throws {
    let vm = try makeVM()
    vm.seed(autoGated)
    #expect(vm.responded)
    #expect(vm.choice == .skip)
    #expect(vm.answeredLine == "Answered automatically · GATED from Easy Run")
}

@Test @MainActor func aManualAnswerOverridesTheAutomaticOne() async throws {
    let provider = GateRespondFakeProvider()
    let vm = try makeVM(provider: provider)
    vm.seed(autoGated)
    vm.undo()                                    // the manual controls come back
    #expect(!vm.responded && vm.answeredLine == nil)
    await vm.respond(choice: .yes)
    #expect(provider.respondCalls.count == 1)
    #expect(vm.choice == .yes && vm.answeredLine == nil)
    vm.seed(autoGated)                           // a stale auto re-seed never hides the manual answer
    #expect(vm.choice == .yes && vm.answeredLine == nil)
}

@Test @MainActor func seedingAManualHubAnswerShowsTheLoggedRowNotTheAutoLine() throws {
    let vm = try makeVM()
    vm.seed(GateAnswer(logId: 3, date: "2026-09-29", choice: "y", source: "manual"))
    #expect(vm.responded && vm.choice == .yes)
    #expect(vm.answeredLine == nil)
}

@Test @MainActor func seedingNilClearsOnlyAnAutomaticAnswer() throws {
    let vm = try makeVM()
    vm.seed(autoGated)
    vm.seed(nil)
    #expect(!vm.responded && vm.answeredLine == nil)
    vm.seed(nil)
    #expect(vm.phase == .idle)
}

@Test func todayAnswerRowTextPrefersTheAutoLine() {
    #expect(gateRespondedRowText(choice: .skip, answeredLine: "Answered automatically · GATED from Easy Run") == "Answered automatically · GATED from Easy Run")
    #expect(gateRespondedRowText(choice: .yes, answeredLine: nil) == "Logged: generate plan")
}

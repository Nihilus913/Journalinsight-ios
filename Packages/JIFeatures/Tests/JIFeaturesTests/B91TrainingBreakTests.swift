import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-B91 (Toby 2026-10-04: "B91 pause should be a manual status"): Settings' "I'm on a break".
private actor StubBreakProvider: TrainingBreakProviding {
    var stored = TrainingBreak(paused: false)
    var fail = false
    var calls: [(Bool, String?)] = []
    func setFail(_ f: Bool) { fail = f }
    func trainingBreak() async throws -> TrainingBreak { stored }
    func setTrainingBreak(paused: Bool, since: String?) async throws -> TrainingBreak {
        calls.append((paused, since))
        if fail { throw HubError.network("offline") }
        stored = TrainingBreak(paused: paused, since: paused ? (since ?? "2026-10-04") : nil)
        return stored
    }
}

@MainActor
struct B91TrainingBreakTests {
    @Test func loadsThenTogglesOnAndOff() async {
        let provider = StubBreakProvider()
        let m = TrainingBreakViewModel(provider: provider)
        await m.load()
        #expect(m.paused == false && m.sinceText == nil)
        await m.set(paused: true)
        #expect(m.paused && m.sinceText == "On a break since 4 Oct")
        await m.set(paused: false)
        #expect(!m.paused && m.sinceText == nil)
        #expect(await provider.calls.map(\.0) == [true, false])
    }

    @Test func failedWriteKeepsTheHubStateAndSaysWhy() async {
        let provider = StubBreakProvider()
        await provider.setFail(true)
        let m = TrainingBreakViewModel(provider: provider, state: TrainingBreak(paused: false))
        await m.set(paused: true)
        #expect(!m.paused)
        #expect(m.errorMessage?.hasPrefix("Could not update the break") == true)
    }

    @Test func dayTextMatchesTheHubCaption() {
        #expect(trainingBreakDayText("2026-09-28") == "28 Sep")
        #expect(trainingBreakDayText("2026-10-01") == "1 Oct")
        #expect(trainingBreakDayText("garbage") == "garbage")
    }

    @Test func settingsRowSitsUnderToday() {
        #expect(SettingsRoot.rows.first { $0.id == "targets" }?.sectionIds.contains(TrainingBreakSection.sectionId) == true)
        #expect(SettingsRegistry.sections.contains { $0.id == TrainingBreakSection.sectionId })
    }
}

import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-B91 (Toby 2026-10-04: "B91 pause should be a manual status"): Settings' "I'm on a break".
private actor StubBreakProvider: TrainingBreakProviding {
    var stored = TrainingBreak(paused: false)
    var fail = false
    var reject = false
    var calls: [(Bool, String?)] = []
    func setFail(_ f: Bool) { fail = f }
    func setReject(_ r: Bool) { reject = r }
    func trainingBreak() async throws -> TrainingBreak { stored }
    func setTrainingBreak(paused: Bool, since: String?) async throws -> TrainingBreak {
        calls.append((paused, since))
        if fail { throw HubError.network("offline") }
        if reject { throw HubError.http(status: 422, detail: "since cannot be in the future") }
        stored = TrainingBreak(paused: paused, since: paused ? (since ?? "2026-10-04") : nil)
        return stored
    }
}

/// 2026-10-04 12:00 in the phone's calendar (B-52 p4 stamps `since` with the phone's day).
private let oct4 = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 12))!

@MainActor
struct B91TrainingBreakTests {
    @Test func loadsThenTogglesOnAndOff() async {
        let provider = StubBreakProvider()
        let m = TrainingBreakViewModel(provider: provider, now: { oct4 })
        await m.load()
        #expect(m.paused == false && m.sinceText == nil)
        await m.set(paused: true)
        #expect(m.paused && m.sinceText == "On a break since 4 Oct")
        await m.set(paused: false)
        #expect(!m.paused && m.sinceText == nil)
        #expect(await provider.calls.map(\.0) == [true, false])
    }

    // B-52 p4: hub unreachable = queued (shown on, pending), not reverted.
    @Test func offlineWriteIsQueuedAndShownPending() async {
        let provider = StubBreakProvider()
        await provider.setFail(true)
        let m = TrainingBreakViewModel(provider: provider, state: TrainingBreak(paused: false), now: { oct4 })
        await m.set(paused: true)
        #expect(m.paused && m.pending && m.errorMessage == nil)
        #expect(m.pendingText != nil && m.sinceText == "On a break since 4 Oct")
    }

    @Test func refusedWriteKeepsTheHubStateAndSaysWhy() async {
        let provider = StubBreakProvider()
        await provider.setReject(true)
        let m = TrainingBreakViewModel(provider: provider, state: TrainingBreak(paused: false))
        await m.set(paused: true)
        #expect(!m.paused && !m.pending)
        #expect(m.errorMessage == "Could not update the break — since cannot be in the future")
    }

    // B-107: a confirmed write re-fetches Decide at once (no relaunch); a failed one does not.
    @Test func confirmedWriteRunsTheRefetchHookOnce() async {
        let provider = StubBreakProvider()
        var fired = 0
        let m = TrainingBreakViewModel(provider: provider, state: TrainingBreak(paused: false),
                                       onChanged: { fired += 1 })
        await m.set(paused: true)
        #expect(fired == 1 && m.paused)
        await m.set(paused: false)
        #expect(fired == 2 && !m.paused)
    }

    @Test func failedWriteNeverRunsTheRefetchHook() async {
        let provider = StubBreakProvider()
        await provider.setFail(true)
        var fired = 0
        let m = TrainingBreakViewModel(provider: provider, state: TrainingBreak(paused: false),
                                       onChanged: { fired += 1 })
        await m.set(paused: true)
        #expect(fired == 0)
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

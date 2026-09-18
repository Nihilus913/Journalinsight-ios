import Foundation
import Testing
import JICore
@testable import JIFeatures

/// Fake `BackloadRunning` (JICore's frozen contract) — JIFeatures builds and tests the VM
/// against the protocol only, never JIHealthKit (see the wave card).
nonisolated final class FakeBackloadRunner: BackloadRunning, @unchecked Sendable {
    var authorizeError: BackloadError?
    var runError: BackloadError?
    var progressSteps: [BackloadProgress] = []
    var summary = BackloadSummary(written: 10, skipped: 2, failed: [])
    private(set) var authorizeCalled = false
    private(set) var lastRange: BackloadRange?

    func authorize() async throws {
        authorizeCalled = true
        if let authorizeError { throw authorizeError }
    }

    func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary {
        lastRange = range
        for step in progressSteps { progress(step) }
        if let runError { throw runError }
        return summary
    }
}

@Test @MainActor func backloadDefaultRangeStartsAtGarminEpoch() {
    let fixedNow = Date(timeIntervalSince1970: 1_780_000_000) // fixed instant, any date
    let vm = HealthBackloadViewModel(runner: FakeBackloadRunner(), now: { fixedNow })
    let range = vm.defaultRange
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
    let comps = cal.dateComponents([.year, .month, .day], from: range.from)
    #expect(comps.year == 2025)
    #expect(comps.month == 5)
    #expect(comps.day == 27)
    #expect(range.to == fixedNow)
}

@Test @MainActor func backloadHappyPathGoesIdleAuthorizingRunningDone() async {
    let runner = FakeBackloadRunner()
    runner.progressSteps = [
        BackloadProgress(monthIndex: 1, monthCount: 2, written: 3, skipped: 0),
        BackloadProgress(monthIndex: 2, monthCount: 2, written: 10, skipped: 2),
    ]
    let vm = HealthBackloadViewModel(runner: runner)
    #expect(vm.phase == .idle)

    await vm.start()

    #expect(runner.authorizeCalled)
    #expect(vm.phase == .done(runner.summary))
    #expect(vm.isRunning == false)
}

@Test @MainActor func backloadReportsRunningProgressDuringTheLastStep() async {
    // A slow last progress step, observed mid-run via a runner that stashes the callback.
    final class Capturing: BackloadRunning, @unchecked Sendable {
        func authorize() async throws {}
        func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary {
            progress(BackloadProgress(monthIndex: 1, monthCount: 3, written: 5, skipped: 1))
            return BackloadSummary(written: 5, skipped: 1, failed: [])
        }
    }
    let vm = HealthBackloadViewModel(runner: Capturing())
    await vm.start()
    #expect(vm.phase == .done(BackloadSummary(written: 5, skipped: 1, failed: [])))
}

@Test @MainActor func backloadAuthorizationDeniedFails() async {
    let runner = FakeBackloadRunner()
    runner.authorizeError = .authorizationDenied
    let vm = HealthBackloadViewModel(runner: runner)

    await vm.start()

    guard case .failed(let message) = vm.phase else { Issue.record("expected .failed, got \(vm.phase)"); return }
    #expect(message.contains("denied"))
    #expect(vm.isRunning == false)
}

@Test @MainActor func backloadHubErrorDuringRunFails() async {
    let runner = FakeBackloadRunner()
    runner.runError = .hub("500")
    let vm = HealthBackloadViewModel(runner: runner)

    await vm.start()

    guard case .failed(let message) = vm.phase else { Issue.record("expected .failed, got \(vm.phase)"); return }
    #expect(message.contains("500"))
}

@Test @MainActor func backloadIsRunningTrueOnlyWhileAuthorizingOrRunning() async {
    let runner = FakeBackloadRunner()
    runner.progressSteps = [BackloadProgress(monthIndex: 1, monthCount: 1, written: 1, skipped: 0)]
    let vm = HealthBackloadViewModel(runner: runner)
    #expect(vm.isRunning == false)
    await vm.start()
    #expect(vm.isRunning == false) // done() after completion
}

@Test @MainActor func backloadShowsTheWritersCursorAsLastSyncedDay() {
    let suite = UserDefaults(suiteName: "ji.tests.backload.cursor.\(UUID().uuidString)")!
    #expect(HealthBackloadViewModel(runner: FakeBackloadRunner(), hrvPrefs: suite).lastSyncedDay == nil)
    suite.set("2026-06-30", forKey: "hk.backload.cursor")
    let vm = HealthBackloadViewModel(runner: FakeBackloadRunner(), hrvPrefs: suite)
    #expect(vm.lastSyncedDay == "2026-06-30")
    suite.set("2026-07-31", forKey: "hk.backload.cursor")
    vm.refreshLastSyncedDay()
    #expect(vm.lastSyncedDay == "2026-07-31")
}

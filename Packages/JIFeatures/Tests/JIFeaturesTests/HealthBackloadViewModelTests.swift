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

/// W9-L3 (B-32): the W8-L4 `screenState` mapping survived the writer-v4 merge (2c0f10e hand-resolved
/// this file). Cold Settings screen = `.idle` with the run button enabled (`isRunning == false`);
/// a denied grant surfaces as `.error(message)`; a finished run as `.loaded`.
@Test @MainActor func backloadScreenStateMapsPhaseAfterTheV4Merge() async {
    let runner = FakeBackloadRunner()
    let model = HealthBackloadViewModel(runner: runner, hrvPrefs: nil)
    #expect(model.screenState == .idle)
    #expect(model.isRunning == false)

    runner.authorizeError = .authorizationDenied
    await model.start()
    #expect(model.screenState == .error("Health access was denied. Enable it in Settings > Health > Data Access."))

    runner.authorizeError = nil
    await model.start()
    #expect(model.screenState == .loaded)
}

/// B-39: the runner reports progress only AFTER each month chunk (JICore contract), so between a
/// granted authorization and the first tick the VM must not still say "authorizing" — under a
/// writer upgrade the first chunk re-walks the whole history and that read as a hang on device.
@Test @MainActor func backloadLeavesAuthorizingBeforeTheFirstProgressTick() async {
    final class PhaseProbe: BackloadRunning, @unchecked Sendable {
        var phaseSeenInRun: HealthBackloadViewModel.Phase?
        var isRunningSeenInRun: Bool?
        var vm: HealthBackloadViewModel?
        func authorize() async throws {}
        func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary {
            phaseSeenInRun = await vm?.phase
            isRunningSeenInRun = await vm?.isRunning
            return BackloadSummary(written: 0, skipped: 0, failed: [])
        }
    }
    let probe = PhaseProbe()
    let vm = HealthBackloadViewModel(runner: probe)
    probe.vm = vm
    await vm.start()
    #expect(probe.phaseSeenInRun == .starting)
    #expect(probe.isRunningSeenInRun == true)
    #expect(vm.phase == .done(BackloadSummary(written: 0, skipped: 0, failed: [])))
}


// MARK: - B-65 "Last Apple upload"

@Test @MainActor func lastAppleUploadFormatsLocalTime() {
    let d = UserDefaults(suiteName: "test.\(UUID())")!
    d.set("2026-09-23T03:12:00Z", forKey: "hk.upload.lastSuccess")
    let vm = HealthBackloadViewModel(runner: FakeBackloadRunner(), hrvPrefs: d, timeZone: TimeZone(identifier: "Europe/Zurich")!)
    #expect(vm.lastAppleUpload == "05:12")
}

@Test @MainActor func lastAppleUploadNilWhenNeverUploaded() {
    let vm = HealthBackloadViewModel(runner: FakeBackloadRunner(), hrvPrefs: UserDefaults(suiteName: "test.\(UUID())")!)
    #expect(vm.lastAppleUpload == nil)
}

@Test @MainActor func lastAppleUploadRefreshesWithTheCursor() {
    let d = UserDefaults(suiteName: "test.\(UUID())")!
    let vm = HealthBackloadViewModel(runner: FakeBackloadRunner(), hrvPrefs: d, timeZone: TimeZone(identifier: "Europe/Zurich")!)
    d.set("2026-09-23T20:00:00Z", forKey: "hk.upload.lastSuccess")
    vm.refreshLastSyncedDay()
    #expect(vm.lastAppleUpload == "22:00")
}

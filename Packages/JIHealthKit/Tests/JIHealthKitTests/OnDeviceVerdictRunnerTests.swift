#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

final class RecordingNotifier: OnDeviceVerdictNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var _posts: [(day: String, verdict: String)] = []
    var posts: [(day: String, verdict: String)] { lock.withLock { _posts } }
    func postVerdict(day: String, result: OnDeviceVerdictResult) async {
        lock.withLock { _posts.append((day, result.verdict)) }
    }
}

/// W-ONDEVICE O-9: the trigger. HK background delivery (sleep + HRV, `.immediate`) ->
/// idempotent `run(day)` -> a local notification only on the first complete night or a verdict
/// change; a locked phone falls back (05:10 floor stays scheduled) and retries on unlock.
@Suite struct OnDeviceVerdictRunnerTests {
    private func result(_ verdict: String, nights: Int = 28) -> OnDeviceVerdictResult {
        OnDeviceVerdictResult(verdict: verdict, reason: nil, sessionPrescription: nil, signals: [], baselineNights: nights)
    }

    @Test func observerFiringThreeTimesPostsOneNotification() async {
        let notifier = RecordingNotifier()
        let runner = OnDeviceVerdictRunner(compute: { [result] _ in result("GO — Strength A", 28) }, notifier: notifier)
        async let a = runner.run(day: "2026-10-04")
        async let b = runner.run(day: "2026-10-04")
        async let c = runner.run(day: "2026-10-04")
        let outcomes = await [a, b, c]
        #expect(notifier.posts.count == 1)
        #expect(outcomes.filter { $0 == .notified }.count == 1)
        #expect(outcomes.filter { $0 == .unchanged }.count == 2)
    }

    @Test func aChangedVerdictNotifiesAgainTheSameDay() async {
        let notifier = RecordingNotifier()
        let verdicts = LockedBox(["GO — Strength A", "GO — Strength A", "MODIFY — Z2 only"])
        let runner = OnDeviceVerdictRunner(compute: { [result] _ in result(verdicts.value.removeFirst(), 28) }, notifier: notifier)
        for _ in 0..<3 { _ = await runner.run(day: "2026-10-04") }
        #expect(notifier.posts.map(\.verdict) == ["GO — Strength A", "MODIFY — Z2 only"])
    }

    @Test func incompleteNightIsMissingAndNeverNotifies() async {
        let notifier = RecordingNotifier()
        let runner = OnDeviceVerdictRunner(compute: { _ in nil }, notifier: notifier)
        #expect(await runner.run(day: "2026-10-04") == .missing)
        #expect(notifier.posts.isEmpty)
    }

    @Test func lockedDeviceFallsBackAndRetriesOnUnlock() async {
        let notifier = RecordingNotifier()
        let locked = LockedBox(true)
        let runner = OnDeviceVerdictRunner(compute: { [result] _ in
            if locked.value { throw HKError(.errorDatabaseInaccessible) }
            return result("GO — Strength A", 28)
        }, notifier: notifier)
        #expect(await runner.run(day: "2026-10-04") == .deferredLocked)
        #expect(await runner.pendingDay == "2026-10-04")
        #expect(notifier.posts.isEmpty)
        locked.value = false
        #expect(await runner.protectedDataBecameAvailable() == .notified)
        #expect(await runner.pendingDay == nil)
        #expect(notifier.posts.count == 1)
        // Nothing pending -> unlock is a no-op.
        #expect(await runner.protectedDataBecameAvailable() == nil)
    }

    @Test func otherErrorsAreReportedNotRetried() async {
        struct Boom: Error {}
        let runner = OnDeviceVerdictRunner(compute: { _ in throw Boom() }, notifier: RecordingNotifier())
        if case .failed = await runner.run(day: "2026-10-04") {} else { Issue.record("expected .failed") }
        #expect(await runner.pendingDay == nil)
    }

    @Test func notifiedVerdictSurvivesARelaunchThroughTheMemory() async {
        let memory = InMemoryVerdictMemory()
        let first = RecordingNotifier()
        _ = await OnDeviceVerdictRunner(compute: { [result] _ in result("GO — Strength A", 28) }, notifier: first, memory: memory).run(day: "2026-10-04")
        let second = RecordingNotifier()
        let relaunched = OnDeviceVerdictRunner(compute: { [result] _ in result("GO — Strength A", 28) }, notifier: second, memory: memory)
        #expect(await relaunched.run(day: "2026-10-04") == .unchanged)
        #expect(second.posts.isEmpty)
    }

    @Test func everyComputedResultReachesTheObserverWithItsLatency() async {
        let seen = LockedBox<[String]>([])
        let runner = OnDeviceVerdictRunner(
            compute: { [result] _ in result("GO — Strength A", 28) }, notifier: RecordingNotifier(),
            onResult: { day, r, _ in seen.value.append("\(day) \(r.verdict)") }
        )
        _ = await runner.run(day: "2026-10-04")
        _ = await runner.run(day: "2026-10-04")
        #expect(seen.value == ["2026-10-04 GO — Strength A", "2026-10-04 GO — Strength A"])
    }

    @Test func protectedDataErrorIsRecognised() {
        #expect(OnDeviceVerdictRunner.isProtectedDataError(HKError(.errorDatabaseInaccessible)))
        #expect(!OnDeviceVerdictRunner.isProtectedDataError(HKError(.errorAuthorizationDenied)))
        #expect(!OnDeviceVerdictRunner.isProtectedDataError(ProviderError.missing("x")))
    }

    // MARK: - Pre-warm schedule

    @Test func prewarmIsAskedForAt0445TheNextMorning() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let evening = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21))!
        let early = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 3))!
        let after = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 5))!
        let expected4 = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 4, minute: 45))!
        let expected5 = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 4, minute: 45))!
        #expect(OnDevicePrewarm.nextBegin(after: evening, calendar: cal) == expected4)
        #expect(OnDevicePrewarm.nextBegin(after: early, calendar: cal) == expected4)
        #expect(OnDevicePrewarm.nextBegin(after: after, calendar: cal) == expected5)
    }

    // MARK: - Uploader wiring

    @Test func uploaderObservesSleepAndHrvImmediatelyAndCallsTheNightHook() async throws {
        guard let rmssd = HKReadKind.hrvRMSSDQuantityType else { return }
        let store = FakeHealthStoreReader()
        let rhrType = HKReadKind.restingHeartRate.sampleType!
        let sleepType = HKReadKind.sleepAnalysis.sampleType!
        let specs = [
            HKMetricSpec(sampleType: rhrType, metricName: "resting_heart_rate", units: "count/min", backgroundFrequency: .hourly) { _ in [] },
            HKMetricSpec(sampleType: sleepType, metricName: "sleep_analysis", units: "hr", backgroundFrequency: .hourly) { _ in [] },
            HKMetricSpec(sampleType: rmssd, metricName: "heart_rate_variability_rmssd", units: "ms", backgroundFrequency: .hourly) { _ in [] },
        ]
        let hub = HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: UploadCapturingURLProtocol.session())
        let uploader = HealthKitUploader(store: store, hub: hub, specs: specs, defaults: UserDefaults(suiteName: "ondevice-\(UUID())"))
        let calls = LockedBox(0)
        _ = try await uploader.startBackgroundDelivery(onNight: { calls.value += 1 })
        #expect(store.backgroundDeliveryEnabled[sleepType.identifier] == .immediate)
        #expect(store.backgroundDeliveryEnabled[rmssd.identifier] == .immediate)
        #expect(store.backgroundDeliveryEnabled[rhrType.identifier] == .hourly)

        for id in [sleepType.identifier, rmssd.identifier, rhrType.identifier] {
            let done = LockedBox(false)
            store.observerHandlers[id]?({ done.value = true })
            for _ in 0..<200 where !done.value { try await Task.sleep(for: .milliseconds(5)) }
            #expect(done.value)
        }
        #expect(calls.value == 2)
    }

    @Test func withoutTheHookTheUploaderKeepsItsOwnFrequencies() async throws {
        let store = FakeHealthStoreReader()
        let sleepType = HKReadKind.sleepAnalysis.sampleType!
        let specs = [HKMetricSpec(sampleType: sleepType, metricName: "sleep_analysis", units: "hr", backgroundFrequency: .hourly) { _ in [] }]
        let hub = HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: UploadCapturingURLProtocol.session())
        _ = try await HealthKitUploader(store: store, hub: hub, specs: specs, defaults: nil).startBackgroundDelivery()
        #expect(store.backgroundDeliveryEnabled[sleepType.identifier] == .hourly)
    }

    // MARK: - Budget

    /// O-9 budget: refresh + store read + the real JICompute verdict for a 120-day (x2 sources) fixture < 2 s.
    @Test func computeBudgetFor120DaysIsUnderTwoSeconds() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let fixed = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 6))!
        let store = FakeBaselineStore()
        var nights: [OnDeviceNight] = []
        for i in 1...120 {
            let key = OnDeviceSeed.addDays(-i, to: "2026-10-04")!
            nights.append(OnDeviceNight(source: .apple, date: key, hrvRmssdMs: 40 + Double(i % 9), rhrBpm: 50, sleepDurationSec: 26_000, sleepScore: 80))
            nights.append(OnDeviceNight(source: .garmin, date: key, hrvRmssdMs: 46, rhrBpm: 48, sleepDurationSec: 25_000, sleepScore: 75))
        }
        nights.append(OnDeviceNight(source: .apple, date: "2026-10-04", hrvRmssdMs: 41))
        try store.record(nights, today: "2026-10-04")
        let p = HealthKitProvider(store: FakeHealthStoreReader(), calendar: cal, now: { fixed }, sourceBundle: { _ in nil },
                                  baseline: store, onDevice: JIComputeVerdictEngine())
        let clock = ContinuousClock()
        let elapsed = try await clock.measure { _ = try await p.onDeviceVerdict(day: "2026-10-04") }
        #expect(elapsed < .seconds(2))
    }
}
#endif

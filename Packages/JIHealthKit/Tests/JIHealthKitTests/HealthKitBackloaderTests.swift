#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

@Suite(.serialized) struct HealthKitBackloaderTests {
    init() { DynamicStubURLProtocol.reset() }

    private var zurich: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        zurich.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func hubClient() -> BackloadClient {
        BackloadClient(hub: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: DynamicStubURLProtocol.session()))
    }
    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "w2h.test.\(UUID().uuidString)")!
    }

    /// Collects `BackloadProgress` from the `@Sendable` progress closure — a plain `var` capture
    /// is a strict-concurrency error there, even though `run` invokes the closure synchronously.
    private final class ProgressCollector: @unchecked Sendable {
        private(set) var events: [BackloadProgress] = []
        func append(_ p: BackloadProgress) { events.append(p) }
    }

    @Test func writesMonthChunksInOrderAndReportsProgress() async throws {
        let store = FakeHealthStore()
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 7, 17))

        let collector = ProgressCollector()
        let summary = try await backloader.run(range) { collector.append($0) }
        let progresses = collector.events

        #expect(DynamicStubURLProtocol.requestedFroms == ["2025-05-27", "2025-06-01", "2025-07-01"])
        #expect(progresses.map(\.monthIndex) == [1, 2, 3])
        #expect(progresses.allSatisfy { $0.monthCount == 3 })
        #expect(progresses.last?.written == 3)
        #expect(summary.written == 3)
        #expect(summary.skipped == 0)
        #expect(summary.failed.isEmpty)
        #expect(store.savedObjects.count == 3)
    }

    @Test func resumesFromPersistedCursorAndSkipsCompletedRange() async throws {
        let store = FakeHealthStore()
        let defaults = testDefaults()
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 7, 17))

        let first = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        _ = try await first.run(range) { _ in }
        #expect(DynamicStubURLProtocol.requestedFroms.count == 3)

        DynamicStubURLProtocol.reset()
        let second = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        let summary = try await second.run(range) { _ in }

        #expect(DynamicStubURLProtocol.requestedFroms.isEmpty) // cursor already at range.to -> no chunks
        #expect(summary.written == 0)
        #expect(summary.skipped == 0)
    }

    @Test func skipsSamplesTheFakeStoreAlreadyHolds() async throws {
        let store = FakeHealthStore()
        store.existing[HKQuantityType(.stepCount).identifier] = ["steps:2025-06-01"]
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let range = BackloadRange(from: day(2025, 6, 1), to: day(2025, 6, 30))

        let summary = try await backloader.run(range) { _ in }

        #expect(summary.written == 0)
        #expect(summary.skipped == 1)
        #expect(store.savedObjects.isEmpty)
    }

    @Test func authorizeThrowsWhenHealthDataUnavailable() async {
        let store = FakeHealthStore()
        store.isHealthDataAvailable = false
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        await #expect(throws: BackloadError.healthDataUnavailable) {
            try await backloader.authorize()
        }
    }

    @Test func authorizeMapsStoreErrorToAuthorizationDenied() async {
        struct SomeError: Error {}
        let store = FakeHealthStore()
        store.authorizationError = SomeError()
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        await #expect(throws: BackloadError.authorizationDenied) {
            try await backloader.authorize()
        }
        #expect(store.authorizationRequested)
    }

    // MARK: - v2

    private let stagedSleepJSON = """
    {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
     "sleep":[{"sync_id":"sleep:2026-06-01","start":"2026-06-01T22:00:00+02:00","end":"2026-06-02T06:00:00+02:00",
       "asleep_sec":28000,"deep_sec":5000,"light_sec":15000,"rem_sec":4000,"awake_sec":800,
       "stages":[{"stage":"light","start":"2026-06-01T22:00:00+02:00","end":"2026-06-01T23:00:00+02:00"}]}],
     "rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[]}
    """

    @Test func stagedSleepDeletesLegacyAsleepMarkerBeforeWritingStages() async throws {
        let store = FakeHealthStore()
        store.existing[HKCategoryType(.sleepAnalysis).identifier] = ["sleep:2026-06-01:asleep"]
        DynamicStubURLProtocol.customResponseJSON = stagedSleepJSON
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await backloader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        #expect(store.deletedSyncIds[HKCategoryType(.sleepAnalysis).identifier] == ["sleep:2026-06-01:asleep"])
        // inBed + 1 stage written; no generic `:asleep` object among them
        let savedIds = store.savedObjects.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
        #expect(Set(savedIds) == ["sleep:2026-06-01:inbed", "sleep:2026-06-01:st0"])
        #expect(!savedIds.contains("sleep:2026-06-01:asleep"))
        #expect(summary.written == 2)
    }

    private let stepBucketJSON = """
    {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
     "sleep":[],"rhr":[],
     "steps":[{"sync_id":"steps:2026-06-01","date":"2026-06-01","count":9000}],
     "energy":[],"vo2max":[],"workouts":[],
     "step_buckets":[{"sync_id":"steps:2026-06-01:0000","start":"2026-06-01T00:00:00+02:00","end":"2026-06-01T00:15:00+02:00","count":40}]}
    """

    @Test func stepBucketsDeleteLegacyDailyStepsSample() async throws {
        let store = FakeHealthStore()
        store.existing[HKQuantityType(.stepCount).identifier] = ["steps:2026-06-01"]
        DynamicStubURLProtocol.customResponseJSON = stepBucketJSON
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        _ = try await backloader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        #expect(store.deletedSyncIds[HKQuantityType(.stepCount).identifier] == ["steps:2026-06-01"])
        let savedIds = store.savedObjects.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
        #expect(savedIds == ["steps:2026-06-01:0000"])
    }

    private let hrvJSON = """
    {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
     "sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[],
     "hrv":[{"sync_id":"hrv:2026-06-01","date":"2026-06-01","nightly_rmssd_ms":42.0,
       "readings":[{"ts":"2026-06-01T23:00:00+02:00","rmssd_ms":40.0}]}]}
    """

    @Test func hrvIsSkippedByDefaultAndWrittenWhenPrefIsOn() async throws {
        let storeOff = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = hrvJSON
        let off = HealthKitBackloader(hub: hubClient(), store: storeOff, defaults: testDefaults())
        let summaryOff = try await off.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
        #expect(summaryOff.written == 0)
        #expect(storeOff.savedObjects.isEmpty)

        DynamicStubURLProtocol.reset()
        DynamicStubURLProtocol.customResponseJSON = hrvJSON
        let storeOn = FakeHealthStore()
        let defaultsOn = testDefaults()
        defaultsOn.set(true, forKey: "hk.backload.writeHRV")
        let on = HealthKitBackloader(hub: hubClient(), store: storeOn, defaults: defaultsOn)
        let summaryOn = try await on.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
        #expect(summaryOn.written == 1)
        let savedIds = storeOn.savedObjects.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
        #expect(savedIds == ["hrv:2026-06-01:2026-06-01T23:00:00+02:00"])
    }

    @Test func heartRateRespirationSpo2WriteToTheirOwnQuantityTypes() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
         "sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[],
         "heart_rate":[{"ts":"2026-06-01T22:31:00+02:00","bpm":58}],
         "respiration":[{"ts":"2026-06-01T22:31:00+02:00","brpm":14}],
         "spo2":[{"ts":"2026-06-01T22:31:00+02:00","pct":96}]}
        """
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await backloader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
        #expect(summary.written == 3)
        let types = Set(store.savedObjects.compactMap { ($0 as? HKSample)?.sampleType.identifier })
        #expect(types == [
            HKQuantityType(.heartRate).identifier,
            HKQuantityType(.respiratoryRate).identifier,
            HKQuantityType(.oxygenSaturation).identifier,
        ])
    }
}
#endif

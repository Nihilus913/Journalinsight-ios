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

        // Two hub requests per chunk now — a daily pass then a dense pass (see
        // `BackloadMonthChunker`) — so each `from` appears twice, in order.
        #expect(DynamicStubURLProtocol.requestedFroms == [
            "2025-05-27", "2025-05-27", "2025-06-01", "2025-06-01", "2025-07-01", "2025-07-01",
        ])
        #expect(progresses.map(\.monthIndex) == [1, 2, 3])
        #expect(progresses.allSatisfy { $0.monthCount == 3 })
        #expect(progresses.last?.written == 3)
        #expect(summary.written == 3)
        #expect(summary.skipped == 0)
        #expect(summary.failed.isEmpty)
        #expect(store.savedObjects.count == 3)
    }

    @Test func resumesFromAMidRunCursorButACompletedRunWalksEverythingAgain() async throws {
        let store = FakeHealthStore()
        let defaults = testDefaults()
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 7, 17))

        // A killed run left the cursor at the end of June -> only July is fetched.
        defaults.set("2025-06-30", forKey: "hk.backload.cursor")
        defaults.set(HealthKitBackloader.writerVersion, forKey: "hk.backload.writerVersion") // not an upgrade
        let resumed = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        _ = try await resumed.run(range) { _ in }
        #expect(DynamicStubURLProtocol.requestedFroms.count == 2) // 1 chunk x (daily + dense)
        #expect(defaults.string(forKey: "hk.backload.cursor") == nil)          // completed -> cleared
        #expect(defaults.string(forKey: "hk.backload.lastCompletedDay") == "2025-07-17")

        // Completed -> the next run walks all 3 chunks again (re-runs force-overwrite workouts).
        DynamicStubURLProtocol.reset()
        let second = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        _ = try await second.run(range) { _ in }
        #expect(DynamicStubURLProtocol.requestedFroms.count == 6)
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

    /// v4 (B-30, audit D7): Garmin's readings ARE RMSSD, so they go under Apple's native iOS-27
    /// `heartRateVariabilityRMSSD` type unconditionally — no `hk.backload.writeHRV` toggle any
    /// more. On an OS without the RMSSD type the specs are dropped rather than mis-filed as SDNN.
    @Test func hrvIsAlwaysWrittenUnderTheRMSSDTypeWithNoToggle() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = hrvJSON
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        guard let rmssd = HKReadKind.hrvRMSSDQuantityType else {
            #expect(summary.written == 0)
            #expect(store.savedObjects.isEmpty)
            return
        }
        #expect(summary.written == 1)
        let saved = store.savedObjects.compactMap { $0 as? HKQuantitySample }
        #expect(saved.map(\.sampleType.identifier) == [rmssd.identifier])
        #expect(!saved.contains { $0.sampleType == HKQuantityType(.heartRateVariabilitySDNN) })
        #expect(saved.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
                == ["hrv:2026-06-01:2026-06-01T23:00:00+02:00"])
    }

    // MARK: - v4: version-keyed saves (audit D4)

    private func stepsJSON(version: Int?) -> String {
        let v = version.map { "\"version\":\($0)," } ?? ""
        return """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
         "sleep":[],"rhr":[],
         "steps":[{"sync_id":"steps:2026-06-01",\(v)"date":"2026-06-01","count":9000}],
         "energy":[],"vo2max":[],"workouts":[]}
        """
    }

    @Test func aHigherHubVersionReplacesTheSampleAlreadyInHealth() async throws {
        let store = FakeHealthStore()
        store.existingVersions[HKQuantityType(.stepCount).identifier] = ["steps:2026-06-01": 1_789_729_100]
        DynamicStubURLProtocol.customResponseJSON = stepsJSON(version: 1_789_729_180)
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        #expect(summary.written == 1)
        #expect(summary.skipped == 0)
        let saved = try #require(store.savedObjects.first as? HKQuantitySample)
        #expect(saved.metadata?[HKMetadataKeySyncVersion] as? Int == 1_789_729_180)
    }

    @Test func anEqualOrLowerHubVersionIsSkipped() async throws {
        for hubVersion in [1_789_729_180, 1_789_729_000] {
            DynamicStubURLProtocol.reset()
            let store = FakeHealthStore()
            store.existingVersions[HKQuantityType(.stepCount).identifier] = ["steps:2026-06-01": 1_789_729_180]
            DynamicStubURLProtocol.customResponseJSON = stepsJSON(version: hubVersion)
            let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
            let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
            #expect(summary.written == 0, "hub version \(hubVersion)")
            #expect(summary.skipped == 1, "hub version \(hubVersion)")
            #expect(store.savedObjects.isEmpty)
        }
    }

    @Test func aVersionlessEntryFallsBackToSyncVersionTwoAndStillSkipsAnExistingSample() async throws {
        let store = FakeHealthStore()
        store.existingVersions[HKQuantityType(.stepCount).identifier] = ["steps:2026-06-01": 2]
        DynamicStubURLProtocol.customResponseJSON = stepsJSON(version: nil)
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
        #expect(summary.written == 0 && summary.skipped == 1)
    }

    @Test func workoutsCarryTheHubVersionAndFallBackToThree() async throws {
        let withVersion = """
        {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
         "workouts":[{"sync_id":"workout:1","version":1789729180,"start":"2026-06-01T07:00:00+02:00","end":"2026-06-01T07:30:00+02:00","kind":"running","name":"Base","kcal":300,"distance_m":5000,"avg_hr":150}]}
        """
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = withVersion
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        _ = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
        let workout = try #require(store.savedObjects.compactMap { $0 as? HKWorkout }.first)
        #expect(workout.metadata?[HKMetadataKeySyncVersion] as? Int == 1_789_729_180)
        let attached = store.associated["workout:1"] ?? []
        #expect(attached.allSatisfy { $0.metadata?[HKMetadataKeySyncVersion] as? Int == 1_789_729_180 })

        DynamicStubURLProtocol.reset()
        DynamicStubURLProtocol.customResponseJSON = withVersion.replacingOccurrences(of: "\"version\":1789729180,", with: "")
        let plain = FakeHealthStore()
        let loader2 = HealthKitBackloader(hub: hubClient(), store: plain, defaults: testDefaults())
        _ = try await loader2.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
        let w2 = try #require(plain.savedObjects.compactMap { $0 as? HKWorkout }.first)
        #expect(w2.metadata?[HKMetadataKeySyncVersion] as? Int == 3)
    }

    // MARK: - v4: one-time upgrade pass (audit D1, D3, D7)

    /// Seeds the three kinds of junk writer v3 left in Health: 96-per-day zero step buckets for a
    /// day the hub no longer serves buckets for, negative respiratory-rate sentinels, and Garmin
    /// RMSSD readings filed under the SDNN type.
    private func seedV3Junk(_ store: FakeHealthStore) {
        let t = day(2026, 6, 1).addingTimeInterval(3600)
        store.preexisting = [
            HKQuantitySample(type: HKQuantityType(.stepCount), quantity: HKQuantity(unit: .count(), doubleValue: 0),
                             start: t, end: t.addingTimeInterval(900),
                             metadata: [HKMetadataKeySyncIdentifier: "steps:2026-06-01:0100", HKMetadataKeySyncVersion: 2]),
            HKQuantitySample(type: HKQuantityType(.respiratoryRate), quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: -2),
                             start: t, end: t, metadata: [HKMetadataKeySyncIdentifier: "resp:2026-06-01T01:00:00+02:00", HKMetadataKeySyncVersion: 2]),
            HKQuantitySample(type: HKQuantityType(.respiratoryRate), quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: 14),
                             start: t, end: t, metadata: [HKMetadataKeySyncIdentifier: "resp:2026-06-01T01:05:00+02:00", HKMetadataKeySyncVersion: 2]),
            HKQuantitySample(type: HKQuantityType(.heartRateVariabilitySDNN), quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 40),
                             start: t, end: t, metadata: [HKMetadataKeySyncIdentifier: "hrv:2026-06-01", HKMetadataKeySyncVersion: 2]),
        ]
    }

    @Test func upgradingFromWriterV3DeletesZeroBucketsNegativeRespAndSDNNSamples() async throws {
        let store = FakeHealthStore()
        seedV3Junk(store)
        let defaults = testDefaults()
        defaults.set(3, forKey: "hk.backload.writerVersion")
        // No `step_buckets` for 2026-06-01 -> the hub says that day has none, so the v3
        // `steps:<date>:HHMM` buckets must go and the daily `steps:<date>` sample stands.
        DynamicStubURLProtocol.customResponseJSON = stepsJSON(version: 1_789_729_180)
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        _ = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        #expect(store.deletedSyncIds[HKQuantityType(.stepCount).identifier]?.contains("steps:2026-06-01:0100") == true)
        #expect(store.deletedSyncIds[HKQuantityType(.respiratoryRate).identifier] == ["resp:2026-06-01T01:00:00+02:00"])
        #expect(store.deletedSyncIds[HKQuantityType(.heartRateVariabilitySDNN).identifier] == ["hrv:2026-06-01"])
        // the daily steps sample is re-saved, not deleted
        let savedIds = store.savedObjects.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
        #expect(savedIds.contains("steps:2026-06-01"))
        #expect(defaults.integer(forKey: "hk.backload.writerVersion") == HealthKitBackloader.writerVersion)
    }

    @Test func theUpgradePassNeverRunsAgainOnceTheStoredWriterVersionIsFour() async throws {
        let store = FakeHealthStore()
        seedV3Junk(store)
        let defaults = testDefaults()
        defaults.set(HealthKitBackloader.writerVersion, forKey: "hk.backload.writerVersion")
        DynamicStubURLProtocol.customResponseJSON = stepsJSON(version: 1_789_729_180)
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        _ = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        #expect(store.whereDeleteCalls == 0)
        #expect(store.deletedSyncIds.isEmpty)
    }

    @Test func daysThatStillHaveBucketsKeepTheirBucketSamples() async throws {
        let store = FakeHealthStore()
        seedV3Junk(store)
        let defaults = testDefaults()
        defaults.set(3, forKey: "hk.backload.writerVersion")
        DynamicStubURLProtocol.customResponseJSON = stepBucketJSON
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        _ = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        // 2026-06-01 has buckets in this chunk's dense response, so its `steps:<date>:HHMM`
        // samples are left alone (only the legacy daily `steps:<date>` is deleted, as in v2/v3).
        #expect(store.deletedSyncIds[HKQuantityType(.stepCount).identifier]?.contains("steps:2026-06-01:0100") != true)
    }

    /// Regression for the W2i fixer finding: `run()` used to call `hub.fetch(from:to:)` with no
    /// `kinds` at all, so the hub's default (`DAILY_KINDS`) meant stages/heart_rate/respiration/
    /// spo2/hrv/step_buckets were never requested and always came back `[]`. Assert the two
    /// fetches per chunk actually carry the daily-pass and dense-pass kind sets.
    @Test func fetchesADailyPassThenADensePassEachCarryingKinds() async throws {
        let store = FakeHealthStore()
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        _ = try await backloader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        #expect(DynamicStubURLProtocol.requestedKinds.count == 2)
        let dailySent = Set((DynamicStubURLProtocol.requestedKinds[0] ?? "").split(separator: ",").map(String.init))
        let denseSent = Set((DynamicStubURLProtocol.requestedKinds[1] ?? "").split(separator: ",").map(String.init))
        #expect(dailySent == BackloadMonthChunker.dailyPassKinds)
        #expect(denseSent == BackloadMonthChunker.densePassKinds)
        // The dense pass is the one that can ever produce stage bars / dense HR / SpO2 / HRV /
        // step buckets on device — it must include `stages` (and `sleep`, so stages land inside
        // populated `sleep[]` entries) alongside every other dense series.
        #expect(denseSent.isSuperset(of: ["stages", "sleep", "heart_rate", "respiration", "spo2", "hrv_readings", "step_buckets"]))
    }

    /// End-to-end reachability check: a hub response that only carries dense-series data under
    /// `sleep[].stages` / `heart_rate` / `respiration` / `spo2` (nothing in the daily-only
    /// fields) must still reach HealthKit. Before the fix this data was unreachable because the
    /// hub was never asked for it in the first place.
    @Test func denseSeriesFromTheDensePassReachesHealthKit() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = stagedSleepJSON
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await backloader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        let savedIds = Set(store.savedObjects.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
        #expect(savedIds.contains("sleep:2026-06-01:st0")) // the staged interval, not just inBed
        #expect(summary.written == 2)
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

    @Test func workoutsGetEnergyAndDistanceAttachedAndUpgradeDeletesTheOldObject() async throws {
        let store = FakeHealthStore()
        let defaults = testDefaults()
        store.existing[HKWorkoutType.workoutType().identifier] = ["workout:1"] // written by writer v2
        DynamicStubURLProtocol.customResponseJSON = """
        {"from":"2026-06-01","to":"2026-06-30","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
         "workouts":[{"sync_id":"workout:1","start":"2026-06-02T07:00:00+02:00","end":"2026-06-02T07:30:00+02:00","kind":"running","name":"Base","kcal":300,"distance_m":5000,"avg_hr":150,"start_estimated":false}],
         "heart_rate":[],"respiration":[],"spo2":[],"hrv":[],"step_buckets":[],"daily_resp":[],"daily_spo2":[]}
        """
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        let range = BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 30))
        let summary = try await loader.run(range) { _ in }
        #expect(store.deletedSyncIds[HKWorkoutType.workoutType().identifier]?.contains("workout:1") == true)
        let attached = store.associated["workout:1"] ?? []
        #expect(attached.count == 2)
        #expect(attached.contains { $0.sampleType == HKQuantityType(.activeEnergyBurned) })
        #expect(attached.contains { $0.sampleType == HKQuantityType(.distanceWalkingRunning) })
        #expect(summary.written == 3 && summary.failed.isEmpty)
        #expect(defaults.integer(forKey: "hk.backload.writerVersion") == HealthKitBackloader.writerVersion)
        // second run: workouts are force-overwritten (deleted + re-saved), still exactly 2 attached
        store.existing[HKWorkoutType.workoutType().identifier] = ["workout:1"]
        let again = try await loader.run(range) { _ in }
        #expect(again.written == 3 && (store.associated["workout:1"]?.count ?? 0) == 2)
        #expect(store.savedObjects.filter { ($0.metadata?[HKMetadataKeySyncIdentifier] as? String) == "workout:1" }.count == 1)
    }
}
#endif

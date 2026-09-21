#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

// W9 L1 (B-30 P3): writer v5 workout path — HR attached per workout window, indoor flag, brand +
// title metadata, motorcycling filtered, and the one-time v5 upgrade that re-attaches HR exactly once.
// An extension of the `.serialized` suite rather than its own: `DynamicStubURLProtocol` is a
// process-wide stub, so these must never run concurrently with the other backloader tests.
extension HealthKitBackloaderTests {
    private var w9Zurich: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }
    private func w9Day(_ y: Int, _ m: Int, _ d: Int) -> Date { w9Zurich.date(from: DateComponents(year: y, month: m, day: d))! }
    private func w9Hub() -> BackloadClient {
        BackloadClient(hub: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: DynamicStubURLProtocol.session()))
    }
    private func w9Defaults() -> UserDefaults { UserDefaults(suiteName: "w9.l1.test.\(UUID().uuidString)")! }

    /// 3 workouts: a treadmill run with 3 HR samples inside, a multi_sport (strength) with 1, a walk
    /// with none; a motorcycling row a stale hub might still send; HR outside every window.
    private var w9JSON: String { """
    {"from":"2026-06-01","to":"2026-06-30","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
     "workouts":[
       {"sync_id":"workout:1","version":1789729180,"start":"2026-06-02T07:00:00+02:00","end":"2026-06-02T07:30:00+02:00","kind":"running","name":"Base","kcal":300,"distance_m":5000,"avg_hr":150,"raw_type":"treadmill_running","indoor":true},
       {"sync_id":"workout:2","version":1789729181,"start":"2026-06-02T18:00:00+02:00","end":"2026-06-02T19:00:00+02:00","kind":"other","name":"Monday","kcal":400,"distance_m":800,"avg_hr":120,"raw_type":"multi_sport","indoor":false},
       {"sync_id":"workout:3","version":1789729182,"start":"2026-06-03T12:00:00+02:00","end":"2026-06-03T12:30:00+02:00","kind":"walking","name":"katzensee","kcal":100,"distance_m":2000,"avg_hr":null,"raw_type":"walking","indoor":false},
       {"sync_id":"workout:9","version":1789729183,"start":"2026-06-04T12:00:00+02:00","end":"2026-06-04T13:00:00+02:00","kind":"other","name":"Ride","kcal":250,"distance_m":60000,"avg_hr":90,"raw_type":"motorcycling_v2","indoor":false}
     ],
     "heart_rate":[
       {"ts":"2026-06-02T06:50:00+02:00","bpm":65},
       {"ts":"2026-06-02T07:00:00+02:00","bpm":95},
       {"ts":"2026-06-02T07:10:00+02:00","bpm":152},
       {"ts":"2026-06-02T07:30:00+02:00","bpm":138},
       {"ts":"2026-06-02T18:20:00+02:00","bpm":118},
       {"ts":"2026-06-04T12:30:00+02:00","bpm":88}
     ],
     "respiration":[],"spo2":[],"hrv":[],"step_buckets":[],"daily_resp":[],"daily_spo2":[]}
    """ }

    private func workouts(in store: FakeHealthStore) -> [String: HKWorkout] {
        Dictionary(uniqueKeysWithValues: store.savedObjects.compactMap { $0 as? HKWorkout }.map { ($0.metadata?[HKMetadataKeySyncIdentifier] as! String, $0) })
    }
    private func hrIds(_ store: FakeHealthStore, _ workout: String) -> [String] {
        (store.associated[workout] ?? []).filter { $0.sampleType == HKQuantityType(.heartRate) }.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
    }

    @Test func heartRateInsideEachWindowIsAttachedAndAWorkoutWithoutHRStillWrites() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = w9JSON
        let loader = HealthKitBackloader(hub: w9Hub(), store: store, defaults: w9Defaults())
        let summary = try await loader.run(BackloadRange(from: w9Day(2026, 6, 1), to: w9Day(2026, 6, 30))) { _ in }
        #expect(summary.failed.isEmpty)

        let saved = workouts(in: store)
        #expect(Set(saved.keys) == ["workout:1", "workout:2", "workout:3"])
        #expect(hrIds(store, "workout:1") == ["workout:1:hr:070000", "workout:1:hr:071000", "workout:1:hr:073000"])
        #expect(hrIds(store, "workout:2") == ["workout:2:hr:182000"])
        #expect(hrIds(store, "workout:3").isEmpty)
        // HR samples carry the workout's version, not the dense-series fallback
        let hr = try #require((store.associated["workout:1"] ?? []).first { $0.sampleType == HKQuantityType(.heartRate) })
        #expect(hr.metadata?[HKMetadataKeySyncVersion] as? Int == 1_789_729_180)
        // the standalone `hr:<ts>` samples are still written (dense series is untouched by L1)
        let standalone = store.savedObjects.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }.filter { $0.hasPrefix("hr:") }
        #expect(standalone.count == 6)
    }

    @Test func indoorBrandTitleAndMultiSportMetadata() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = w9JSON
        let loader = HealthKitBackloader(hub: w9Hub(), store: store, defaults: w9Defaults())
        _ = try await loader.run(BackloadRange(from: w9Day(2026, 6, 1), to: w9Day(2026, 6, 30))) { _ in }
        let saved = workouts(in: store)
        let treadmill = try #require(saved["workout:1"])
        #expect(treadmill.metadata?[HKMetadataKeyIndoorWorkout] as? Bool == true)
        #expect(treadmill.metadata?[HKMetadataKeyWorkoutBrandName] as? String == "Garmin fēnix 8")
        #expect(treadmill.metadata?[HealthKitBackloader.workoutTitleMetadataKey] as? String == "Base")
        #expect(treadmill.workoutActivityType == .running)
        let multi = try #require(saved["workout:2"])
        #expect(multi.workoutActivityType == .traditionalStrengthTraining)
        #expect(multi.metadata?[HKMetadataKeyIndoorWorkout] as? Bool == false)
        #expect(multi.metadata?[HealthKitBackloader.workoutTitleMetadataKey] as? String == "Monday")
        let walk = try #require(saved["workout:3"])
        #expect(walk.metadata?[HKMetadataKeyIndoorWorkout] as? Bool == false)
        #expect(walk.metadata?[HKMetadataKeyWorkoutBrandName] as? String == "Garmin fēnix 8")
    }

    @Test func motorcyclingNeverReachesTheStore() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = w9JSON
        let loader = HealthKitBackloader(hub: w9Hub(), store: store, defaults: w9Defaults())
        _ = try await loader.run(BackloadRange(from: w9Day(2026, 6, 1), to: w9Day(2026, 6, 30))) { _ in }
        #expect(workouts(in: store)["workout:9"] == nil)
        #expect(store.associated["workout:9"] == nil)
        #expect(store.deletedSyncIds[HKWorkoutType.workoutType().identifier]?.contains("workout:9") != true)
    }

    @Test func v5UpgradeReattachesHRForExistingWorkoutsExactlyOnce() async throws {
        let store = FakeHealthStore()
        let defaults = w9Defaults()
        defaults.set(4, forKey: "hk.backload.writerVersion")
        // writer v4 left workout:1 (no HR) and a stale workout-HR sample whose timestamp the hub no
        // longer serves — the upgrade must sweep it, and the force-overwrite path re-attaches the rest.
        store.existing[HKWorkoutType.workoutType().identifier] = ["workout:1"]
        let staleAt = BackloadDateParsing.timestamp("2026-06-02T07:20:00+02:00")!
        store.preexisting = [HKQuantitySample(type: HKQuantityType(.heartRate), quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: 140),
                                              start: staleAt, end: staleAt, metadata: [HKMetadataKeySyncIdentifier: "workout:1:hr:072000", HKMetadataKeySyncVersion: 3])]
        DynamicStubURLProtocol.customResponseJSON = w9JSON
        let loader = HealthKitBackloader(hub: w9Hub(), store: store, defaults: defaults)
        let range = BackloadRange(from: w9Day(2026, 6, 1), to: w9Day(2026, 6, 30))
        _ = try await loader.run(range) { _ in }

        // the v5 workoutHR sweep + (W11) one per-workout `workout:<id>:hr:*` sweep for each of the
        // 3 written workouts; the v4 pass is done
        #expect(store.whereDeleteCalls == 1 + 3)
        // the stale reading is swept by the upgrade; the ids the force-overwrite path deletes-then-
        // re-attaches also land in `deletedSyncIds` (same as energy/distance since v4)
        #expect(store.deletedSyncIds[HKQuantityType(.heartRate).identifier]?.contains("workout:1:hr:072000") == true)
        #expect(store.preexisting.isEmpty)
        #expect(hrIds(store, "workout:1").count == 3)
        #expect(defaults.integer(forKey: "hk.backload.writerVersion") == HealthKitBackloader.writerVersion)

        // second run at the current version: no upgrade sweep (only the 3 per-workout ones),
        // workouts force-overwrite, still exactly 3 HR samples
        _ = try await loader.run(range) { _ in }
        #expect(store.whereDeleteCalls == 4 + 3)
        #expect(hrIds(store, "workout:1").count == 3)
        #expect(store.savedObjects.filter { ($0.metadata?[HKMetadataKeySyncIdentifier] as? String) == "workout:1" }.count == 1)
    }

    @Test func writerVersionIsAtLeastFiveAndTheEnumHasTheWorkoutHRStep() {
        #expect(HealthKitBackloader.writerVersion >= 5) // W11 bumped it to 6
        #expect(HealthKitBackloader.V5Upgrade.allCases.contains(.workoutHR))
    }
}
#endif

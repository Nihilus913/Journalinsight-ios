#if canImport(HealthKit)
import CoreLocation
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

// W11 L1 (B-30 P4): writer v6 workout path — an `HKWorkoutRoute` per workout with GPS points
// (delete-before-insert by sync id), per-second HR from `workout_hr` attached in ONE `add` call,
// the old `workout:<id>:hr:*` samples swept per workout, `HKMetadataKeyElevationAscended` when the
// hub sends an ascent, and a hub without the v4 arrays behaving exactly as W9 did.
// An extension of the `.serialized` suite: `DynamicStubURLProtocol` is process-wide.
extension HealthKitBackloaderTests {
    private var w11Zurich: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }
    private func w11Day(_ y: Int, _ m: Int, _ d: Int) -> Date { w11Zurich.date(from: DateComponents(year: y, month: m, day: d))! }
    private func w11Hub() -> BackloadClient {
        BackloadClient(hub: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: DynamicStubURLProtocol.session()))
    }
    private func w11Defaults() -> UserDefaults { UserDefaults(suiteName: "w11.l1.test.\(UUID().uuidString)")! }
    private var w11Range: BackloadRange { BackloadRange(from: w11Day(2026, 9, 1), to: w11Day(2026, 9, 30)) }

    private static let runId = "workout:24218147086"
    private static let strengthId = "workout:24230557720"

    /// The fixture of record's two entries (6 + 4 samples, 6 points) attached to two workouts, plus
    /// a 2-min dense reading inside the run's window that must be ignored in favour of `workout_hr`.
    private var w11JSON: String { """
    {"from":"2026-09-01","to":"2026-09-30","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
     "workouts":[
       {"sync_id":"workout:24218147086","version":1789729180,"start":"2026-09-03T05:51:00+02:00","end":"2026-09-03T06:09:24+02:00","kind":"running","name":"katzensee","kcal":300,"distance_m":3000,"avg_hr":150,"raw_type":"running","indoor":false},
       {"sync_id":"workout:24230557720","version":1789729181,"start":"2026-09-04T05:58:00+02:00","end":"2026-09-04T06:58:00+02:00","kind":"strength","name":"Thursday","kcal":400,"distance_m":null,"avg_hr":120,"raw_type":"strength_training","indoor":true}
     ],
     "heart_rate":[{"ts":"2026-09-03T05:52:00+02:00","bpm":120}],
     "workout_hr":[
       {"sync_id":"workout:24218147086","version":1790000000,"samples":[
         {"ts":"2026-09-03T03:51:03Z","bpm":109},{"ts":"2026-09-03T03:51:04Z","bpm":108},{"ts":"2026-09-03T03:51:05Z","bpm":108},
         {"ts":"2026-09-03T03:51:06Z","bpm":109},{"ts":"2026-09-03T03:51:07Z","bpm":110},{"ts":"2026-09-03T03:51:08Z","bpm":110}]},
       {"sync_id":"workout:24230557720","version":1790000000,"samples":[
         {"ts":"2026-09-04T03:58:36Z","bpm":93},{"ts":"2026-09-04T03:58:37Z","bpm":93},{"ts":"2026-09-04T03:58:38Z","bpm":98},{"ts":"2026-09-04T03:58:39Z","bpm":99}]}
     ],
     "workout_routes":[
       {"sync_id":"workout:24218147086","version":1790000000,"ascent_m":12.5,"points":[
         {"ts":"2026-09-03T03:51:03Z","lat":47.438225308433175,"lon":8.47419991157949,"alt_m":441.6000061035156,"speed_mps":1.1660000085830688},
         {"ts":"2026-09-03T03:51:04Z","lat":47.43824006058276,"lon":8.474185829982162,"alt_m":441.79998779296875,"speed_mps":1.2410000562667847},
         {"ts":"2026-09-03T03:51:05Z","lat":47.43825942277908,"lon":8.474190691486001,"alt_m":null,"speed_mps":null},
         {"ts":"2026-09-03T03:51:06Z","lat":47.438272750005126,"lon":8.474195804446936,"alt_m":442.0,"speed_mps":1.6890000104904175},
         {"ts":"2026-09-03T03:51:07Z","lat":47.438282892107964,"lon":8.474203683435917,"alt_m":442.20001220703125,"speed_mps":1.7079999446868896},
         {"ts":"2026-09-03T03:51:08Z","lat":47.43829395622015,"lon":8.474223548546433,"alt_m":443.6000061035156,"speed_mps":1.7079999446868896}]}
     ]}
    """ }

    /// Same two workouts from a pre-W11 hub: no `workout_hr`, no `workout_routes`.
    private var preW11JSON: String { """
    {"from":"2026-09-01","to":"2026-09-30","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
     "workouts":[
       {"sync_id":"workout:24218147086","version":1789729180,"start":"2026-09-03T05:51:00+02:00","end":"2026-09-03T06:09:24+02:00","kind":"running","name":"katzensee","kcal":300,"distance_m":3000,"avg_hr":150,"raw_type":"running","indoor":false},
       {"sync_id":"workout:24230557720","version":1789729181,"start":"2026-09-04T05:58:00+02:00","end":"2026-09-04T06:58:00+02:00","kind":"strength","name":"Thursday","kcal":400,"distance_m":null,"avg_hr":120,"raw_type":"strength_training","indoor":true}
     ],
     "heart_rate":[{"ts":"2026-09-03T05:52:00+02:00","bpm":120}]}
    """ }

    private func w11Workouts(in store: FakeHealthStore) -> [String: HKWorkout] {
        Dictionary(uniqueKeysWithValues: store.savedObjects.compactMap { $0 as? HKWorkout }.map { ($0.metadata?[HKMetadataKeySyncIdentifier] as! String, $0) })
    }
    private func w11HR(_ store: FakeHealthStore, _ workout: String) -> [HKQuantitySample] {
        (store.associated[workout] ?? []).compactMap { $0 as? HKQuantitySample }.filter { $0.sampleType == HKQuantityType(.heartRate) }
    }

    @Test func routeIsInsertedWithLocationsMetadataAndDeleteBeforeInsert() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = w11JSON
        let loader = HealthKitBackloader(hub: w11Hub(), store: store, defaults: w11Defaults())
        let summary = try await loader.run(w11Range) { _ in }
        #expect(summary.failed.isEmpty)

        #expect(store.insertedRoutes.count == 1)
        let route = try #require(store.insertedRoutes.first)
        #expect(route.workoutSyncId == Self.runId)
        #expect(route.metadata[HKMetadataKeySyncIdentifier] as? String == "workout:24218147086:route")
        // versioned like the workout and its HR samples (W9 rule) — the route is delete-before-
        // insert, so the version never gates anything; it just re-versions with a hub correction
        #expect((route.metadata[HKMetadataKeySyncVersion] as? NSNumber)?.intValue == 1_789_729_180)
        #expect(route.locations.count == 6)
        let l0 = route.locations[0]
        #expect(l0.coordinate.latitude == 47.438225308433175)
        #expect(l0.coordinate.longitude == 8.47419991157949)
        #expect(l0.altitude == 441.6000061035156)
        #expect(l0.verticalAccuracy >= 0)
        #expect(l0.speed == 1.1660000085830688)
        #expect(l0.timestamp == BackloadDateParsing.timestamp("2026-09-03T03:51:03Z"))
        // a point without elevation/speed marks both invalid rather than inventing 0 m / 0 m/s
        let l2 = route.locations[2]
        #expect(l2.verticalAccuracy < 0)
        #expect(l2.speed < 0)
        #expect(route.locations.map(\.timestamp) == route.locations.map(\.timestamp).sorted())
        // the previous route is deleted by sync id before the new one is inserted
        #expect(store.deletedSyncIds[HKSeriesType.workoutRoute().identifier]?.contains("workout:24218147086:route") == true)
        #expect(store.routeDeletedBeforeInsert[Self.runId] == true)
        // the route is built against the workout object that was saved
        let saved = try #require(w11Workouts(in: store)[Self.runId])
        #expect(route.workout === saved)
    }

    @Test func perSecondHRIsAttachedInOneCallAndAscentLandsOnTheWorkout() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = w11JSON
        let loader = HealthKitBackloader(hub: w11Hub(), store: store, defaults: w11Defaults())
        _ = try await loader.run(w11Range) { _ in }

        let runHR = w11HR(store, Self.runId)
        #expect(runHR.map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) } == [109, 108, 108, 109, 110, 110])
        #expect(runHR.map { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }.first == "workout:24218147086:hr:055103")
        #expect(store.addCalls[Self.runId] == 1) // energy + distance + 6 HR in one `add`
        // the dense 2-min reading inside the window is NOT attached when `workout_hr` exists
        #expect(!runHR.contains { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) == 120 })
        let run = try #require(w11Workouts(in: store)[Self.runId])
        let ascent = try #require(run.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)
        #expect(ascent.doubleValue(for: .meter()) == 12.5)
    }

    @Test func strengthWorkoutGetsHRButNoRoute() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = w11JSON
        let loader = HealthKitBackloader(hub: w11Hub(), store: store, defaults: w11Defaults())
        _ = try await loader.run(w11Range) { _ in }

        #expect(w11HR(store, Self.strengthId).map { $0.quantity.doubleValue(for: HKUnit(from: "count/min")) } == [93, 93, 98, 99])
        #expect(store.insertedRoutes.contains { $0.workoutSyncId == Self.strengthId } == false)
        // the stale-route delete still runs (a route the hub no longer serves must not linger)
        #expect(store.deletedSyncIds[HKSeriesType.workoutRoute().identifier]?.contains("workout:24230557720:route") == true)
        let strength = try #require(w11Workouts(in: store)[Self.strengthId])
        #expect(strength.metadata?[HKMetadataKeyElevationAscended] == nil)
    }

    @Test func staleAttachedHRIsSweptPerWorkoutBeforeReattach() async throws {
        let store = FakeHealthStore()
        let defaults = w11Defaults()
        defaults.set(HealthKitBackloader.writerVersion, forKey: "hk.backload.writerVersion") // no upgrade pass
        // a W9-era 2-min reading the hub no longer serves at that second
        let staleAt = BackloadDateParsing.timestamp("2026-09-03T05:52:00+02:00")!
        store.preexisting = [HKQuantitySample(type: HKQuantityType(.heartRate), quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: 120),
                                              start: staleAt, end: staleAt, metadata: [HKMetadataKeySyncIdentifier: "workout:24218147086:hr:055200", HKMetadataKeySyncVersion: 3])]
        DynamicStubURLProtocol.customResponseJSON = w11JSON
        let loader = HealthKitBackloader(hub: w11Hub(), store: store, defaults: defaults)
        _ = try await loader.run(w11Range) { _ in }

        #expect(store.deletedSyncIds[HKQuantityType(.heartRate).identifier]?.contains("workout:24218147086:hr:055200") == true)
        #expect(store.preexisting.isEmpty)
        #expect(w11HR(store, Self.runId).count == 6)
    }

    @Test func hubWithoutTheV4ArraysBehavesExactlyAsW9() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = preW11JSON
        let loader = HealthKitBackloader(hub: w11Hub(), store: store, defaults: w11Defaults())
        let summary = try await loader.run(w11Range) { _ in }
        #expect(summary.failed.isEmpty)

        #expect(store.insertedRoutes.isEmpty)
        let runHR = w11HR(store, Self.runId)
        #expect(runHR.map { $0.metadata?[HKMetadataKeySyncIdentifier] as? String } == ["workout:24218147086:hr:055200"])
        #expect(w11HR(store, Self.strengthId).isEmpty)
        let run = try #require(w11Workouts(in: store)[Self.runId])
        #expect(run.metadata?[HKMetadataKeyElevationAscended] == nil)
        #expect(Set(w11Workouts(in: store).keys) == [Self.runId, Self.strengthId])
    }

    @Test func writerVersionIsSixAndTheShareSetListsWorkoutRoute() {
        #expect(HealthKitBackloader.writerVersion == 6)
        #expect(HealthKitBackloader.allSampleTypes.contains(HKSeriesType.workoutRoute()))
    }

    @Test func v6BumpRerunsTheWholeRangeOnce() async throws {
        let store = FakeHealthStore()
        let defaults = w11Defaults()
        defaults.set(5, forKey: "hk.backload.writerVersion")
        defaults.set("2026-09-30", forKey: "hk.backload.cursor") // a v5 cursor that would otherwise skip the range
        DynamicStubURLProtocol.customResponseJSON = w11JSON
        let loader = HealthKitBackloader(hub: w11Hub(), store: store, defaults: defaults)
        _ = try await loader.run(w11Range) { _ in }
        #expect(store.insertedRoutes.count == 1)
        #expect(defaults.integer(forKey: "hk.backload.writerVersion") == 6)
    }
}
#endif

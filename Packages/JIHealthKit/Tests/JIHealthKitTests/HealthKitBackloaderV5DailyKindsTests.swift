#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

/// W9 L2 (B-30 P5 + P2.7): floors/distance reach HealthKit as daily samples, the share set covers
/// their types, the v5 upgrade `switch` has a `dailyKinds` step, and the overlap policy runs
/// against `HealthStoreReading.workouts(start:end:)` before a hub workout is written.
///
/// An extension of the `.serialized` `HealthKitBackloaderTests` suite (not a suite of its own):
/// `DynamicStubURLProtocol.customResponseJSON` is process-global, so a second suite would race
/// the first one's stub. Helpers are re-declared `fileprivate` because the suite's own are
/// `private` to its file.
extension HealthKitBackloaderTests {
    private var zurichL2: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        zurichL2.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func at(_ h: Int, _ m: Int) -> Date {
        zurichL2.date(from: DateComponents(year: 2026, month: 6, day: 2, hour: h, minute: m))!
    }
    private func hubClient() -> BackloadClient {
        BackloadClient(hub: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: DynamicStubURLProtocol.session()))
    }
    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "w9l2.test.\(UUID().uuidString)")!
    }

    private var floorsDistanceJSON: String { """
    {"from":"2026-06-01","to":"2026-06-01","source":"garmin_api",
     "sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],"workouts":[],
     "floors":[{"sync_id":"floors:2026-06-01","version":1789729180,"date":"2026-06-01","count":12}],
     "distance":[{"sync_id":"distance:2026-06-01","version":1789729180,"date":"2026-06-01","meters":6420.5}]}
    """ }

    @Test func floorsAndDistanceAreWrittenAsDailySamplesCarryingTheHubVersion() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = floorsDistanceJSON
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }

        #expect(summary.written == 2 && summary.failed.isEmpty)
        let saved = store.savedObjects.compactMap { $0 as? HKQuantitySample }
        let floors = try #require(saved.first { $0.sampleType == HKQuantityType(.flightsClimbed) })
        let distance = try #require(saved.first { $0.sampleType == HKQuantityType(.distanceWalkingRunning) })
        #expect(floors.quantity.doubleValue(for: .count()) == 12)
        #expect(distance.quantity.doubleValue(for: .meter()) == 6420.5) // net figure as sent, never re-subtracted
        for sample in [floors, distance] {
            #expect((sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue == 1789729180)
            #expect(sample.startDate == day(2026, 6, 1))
            #expect(sample.endDate == day(2026, 6, 2).addingTimeInterval(-1)) // `dayBounds`: 23:59:59
        }
        #expect(floors.metadata?[HKMetadataKeySyncIdentifier] as? String == "floors:2026-06-01")
        #expect(distance.metadata?[HKMetadataKeySyncIdentifier] as? String == "distance:2026-06-01")
    }

    @Test func theDailyPassRequestsFloorsAndDistance() {
        #expect(BackloadMonthChunker.dailyPassKinds.isSuperset(of: ["floors", "distance"]))
    }

    @Test func theShareSetIncludesFlightsClimbedAndDistanceWalkingRunning() {
        #expect(HealthKitBackloader.allSampleTypes.contains(HKQuantityType(.flightsClimbed)))
        #expect(HealthKitBackloader.allSampleTypes.contains(HKQuantityType(.distanceWalkingRunning)))
    }

    @Test func theV5UpgradeSwitchHasADailyKindsStepAndAnOldStoreStillGetsTheNewKinds() async throws {
        #expect(HealthKitBackloader.V5Upgrade.allCases.contains(.dailyKinds))
        let store = FakeHealthStore()
        let defaults = testDefaults()
        defaults.set(3, forKey: "hk.backload.writerVersion")
        DynamicStubURLProtocol.customResponseJSON = floorsDistanceJSON
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 1))) { _ in }
        #expect(summary.written == 2)
        #expect(defaults.integer(forKey: "hk.backload.writerVersion") == HealthKitBackloader.writerVersion)
    }

    // MARK: - P2.7 overlap dedupe

    private func workoutJSON(start: String, end: String) -> String {
        """
        {"from":"2026-06-01","to":"2026-06-30","source":"garmin_api","sleep":[],"rhr":[],"steps":[],"energy":[],"vo2max":[],
         "workouts":[{"sync_id":"workout:1","start":"\(start)","end":"\(end)","kind":"running","name":"Base","kcal":300,"distance_m":5000,"avg_hr":150}]}
        """
    }
    private func whoopWorkout() -> HKWorkout {
        HKWorkout(activityType: .running, start: at(9, 0), end: at(10, 0), workoutEvents: nil,
                  totalEnergyBurned: nil, totalDistance: nil, metadata: nil)
    }

    @Test func aHubWorkoutOverlappingAWhoopWorkoutByTwoThirdsIsSkippedAndItsOldCopyRemoved() async throws {
        let store = FakeHealthStore()
        let reader = FakeHealthStoreReader()
        reader.foreignWorkouts = [whoopWorkout()]
        store.existing[HKWorkoutType.workoutType().identifier] = ["workout:1"] // a v4 run wrote it before the policy existed
        DynamicStubURLProtocol.customResponseJSON = workoutJSON(start: "2026-06-02T09:20:00+02:00", end: "2026-06-02T10:20:00+02:00")
        let loader = HealthKitBackloader(hub: hubClient(), store: store, reader: reader, defaults: testDefaults())
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 30))) { _ in }

        #expect(summary.written == 0 && summary.skipped == 1 && summary.failed.isEmpty)
        #expect(!store.savedObjects.contains { $0 is HKWorkout })
        #expect(store.associated["workout:1"] == nil)
        #expect(store.deletedSyncIds[HKWorkoutType.workoutType().identifier] == ["workout:1"])
        #expect(store.deletedSyncIds[HKQuantityType(.activeEnergyBurned).identifier] == ["workout:1:energy"])
        #expect(reader.workoutQueries.count == 1)
    }

    @Test func aHubWorkoutOverlappingAWhoopWorkoutByOneSixthIsWritten() async throws {
        let store = FakeHealthStore()
        let reader = FakeHealthStoreReader()
        reader.foreignWorkouts = [whoopWorkout()]
        DynamicStubURLProtocol.customResponseJSON = workoutJSON(start: "2026-06-02T09:50:00+02:00", end: "2026-06-02T10:50:00+02:00")
        let loader = HealthKitBackloader(hub: hubClient(), store: store, reader: reader, defaults: testDefaults())
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 30))) { _ in }

        #expect(summary.skipped == 0)
        #expect(store.savedObjects.contains { $0 is HKWorkout })
        #expect(summary.written == 3) // workout + energy + distance, as in v4
    }

    @Test func withoutAReaderTheWorkoutPathIsUnchanged() async throws {
        let store = FakeHealthStore()
        DynamicStubURLProtocol.customResponseJSON = workoutJSON(start: "2026-06-02T09:20:00+02:00", end: "2026-06-02T10:20:00+02:00")
        let loader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let summary = try await loader.run(BackloadRange(from: day(2026, 6, 1), to: day(2026, 6, 30))) { _ in }
        #expect(summary.written == 3 && summary.skipped == 0)
    }

    @Test func authorizeAlsoRequestsWorkoutReadAccessForTheOverlapCheck() async throws {
        let store = FakeHealthStore()
        let reader = FakeHealthStoreReader()
        let loader = HealthKitBackloader(hub: hubClient(), store: store, reader: reader, defaults: testDefaults())
        try await loader.authorize()
        #expect(store.authorizationRequested)
        #expect(reader.requestedReadTypes == [HKWorkoutType.workoutType()])
    }
}
#endif

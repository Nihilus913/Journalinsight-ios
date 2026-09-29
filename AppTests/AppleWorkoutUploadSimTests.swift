import CoreLocation
import Foundation
import HealthKit
import Testing
import JIHealthKit
import JIHub
@testable import JournalInsight

/// W-B81 L2 sim exit (A-4): the three fixture workouts are SAVED into the simulator's HealthKit
/// (`HKWorkoutBuilder` + HR samples + route + effort), then the REAL reader + uploader send them
/// and the captured POST body is compared with the frozen contract
/// (`Packages/JIHealthKit/Tests/JIHealthKitTests/Fixtures/apple_workouts/workouts_payload.json`).
///
/// Opt-in (it needs a one-time tap on the Health access sheet): run with
/// `TEST_RUNNER_JI_B81_SIM_SEED=1 xcodebuild test ... -only-testing:JournalInsightTests/AppleWorkoutUploadSimTests`.
///
/// What HealthKit itself decides (never the uploader) is normalised before comparing, and only that:
/// - `uuid`s — HealthKit assigns object UUIDs on save;
/// - `source` — a seeded workout's source is this app, not "Apple Watch";
/// - `avg_hr_bpm` — HealthKit computes it from the samples (time-weighted), the fixture's is a Watch value;
/// - `effort_estimated` — only Apple writes the estimated score (third-party share is disallowed);
/// - activity `name` — HealthKit has no per-activity title;
/// - `zone_time` — only compared when HealthKit produced a zone group for the seeded workout.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["JI_B81_SIM_SEED"] == "1"))
struct AppleWorkoutUploadSimTests {
    private static let zone = TimeZone(identifier: "Europe/Zurich")!
    private let store = HKHealthStore()

    private static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Packages/JIHealthKit/Tests/JIHealthKitTests/Fixtures/apple_workouts/workouts_payload.json")
    }

    private static func fixtureWorkouts() throws -> [[String: Any]] {
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        return try #require((obj["data"] as? [String: Any])?["workouts"] as? [[String: Any]])
    }

    private static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f.date(from: s)!
    }

    private static func activityType(_ sport: String) -> HKWorkoutActivityType {
        switch sport { case "running": .running; case "cycling": .cycling; default: .other }
    }

    private static func distanceType(_ sport: String) -> HKQuantityType {
        sport == "cycling" ? HKQuantityType(.distanceCycling) : HKQuantityType(.distanceWalkingRunning)
    }

    /// Saves one fixture workout the way a Watch would leave it in Health; returns the saved workout.
    private func seed(_ f: [String: Any]) async throws -> HKWorkout {
        let sport = f["sport"] as! String
        let indoor = f["is_indoor"] as? Bool ?? false
        let start = Self.date(f["start"] as! String), end = Self.date(f["end"] as! String)
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(sport)
        config.locationType = indoor ? .indoor : .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
        try await builder.beginCollection(at: start)

        let bpm = HKUnit.count().unitDivided(by: .minute())
        var samples: [HKSample] = (f["hr_samples"] as! [[String: Any]]).map {
            let ts = Self.date($0["ts"] as! String)
            // Marked as a debug seed: the reader drops this app's own HR (Garmin backload) otherwise.
            return HKQuantitySample(type: HKQuantityType(.heartRate), quantity: HKQuantity(unit: bpm, doubleValue: ($0["bpm"] as! NSNumber).doubleValue), start: ts, end: ts,
                                    metadata: [AppleWorkoutFilter.debugSeedMetadataKey: true])
        }
        if let kcal = (f["kcal"] as? NSNumber)?.doubleValue {
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: end))
        }
        let activities = f["activities"] as! [[String: Any]]
        if activities.isEmpty, let m = (f["distance_m"] as? NSNumber)?.doubleValue {
            samples.append(HKQuantitySample(type: Self.distanceType(sport), quantity: HKQuantity(unit: .meter(), doubleValue: m), start: start, end: end))
        }
        for a in activities {
            let aStart = Self.date(a["start"] as! String), aEnd = Self.date(a["end"] as! String)
            let aConfig = HKWorkoutConfiguration()
            aConfig.activityType = Self.activityType(a["sport"] as! String)
            aConfig.locationType = config.locationType
            try await builder.addWorkoutActivity(HKWorkoutActivity(workoutConfiguration: aConfig, start: aStart, end: aEnd, metadata: nil))
            if let m = (a["distance_m"] as? NSNumber)?.doubleValue {
                samples.append(HKQuantitySample(type: Self.distanceType(sport), quantity: HKQuantity(unit: .meter(), doubleValue: m), start: aStart, end: aEnd))
            }
        }
        try await builder.addSamples(samples)
        if let zones = f["zone_time"] as? [[String: Any]] {
            let bounds = zones.compactMap { ($0["upper_bpm"] as? NSNumber)?.doubleValue }.map { HKQuantity(unit: bpm, doubleValue: $0) }
            try? await builder.setCustomZoneConfiguration(try HKWorkoutZoneConfiguration(quantityType: HKQuantityType(.heartRate), zoneBoundaries: bounds),
                                                          for: HKQuantityType(.heartRate))
        }
        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: indoor, AppleWorkoutFilter.debugSeedMetadataKey: true])
        try await builder.endCollection(at: end)
        let workout = try #require(try await builder.finishWorkout())

        let route = (f["route"] as! [[String: Any]]).map {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: ($0["lat"] as! NSNumber).doubleValue, longitude: ($0["lon"] as! NSNumber).doubleValue),
                       altitude: ($0["elevation_m"] as! NSNumber).doubleValue, horizontalAccuracy: ($0["h_accuracy_m"] as! NSNumber).doubleValue,
                       verticalAccuracy: 3, course: -1, speed: ($0["speed_mps"] as! NSNumber).doubleValue,
                       timestamp: Self.date($0["ts"] as! String))
        }
        if !route.isEmpty {
            let rb = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            try await rb.insertRouteData(route)
            _ = try await rb.finishRoute(with: workout, metadata: nil)
        }
        if let effort = (f["effort_user"] as? NSNumber)?.doubleValue {
            let s = HKQuantitySample(type: HKQuantityType(.workoutEffortScore), quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: effort), start: start, end: end)
            try await store.save(s)
            try await store.relateWorkoutEffortSample(s, with: workout, activity: nil)
        }
        return workout
    }

    private func normalised(_ got: [String: Any], like want: [String: Any]) -> ([String: Any], [String: Any]) {
        var g = got, w = want
        for k in ["uuid", "source", "avg_hr_bpm", "effort_estimated"] { g[k] = nil; w[k] = nil }
        if g["zone_time"] == nil { w["zone_time"] = nil }
        func strip(_ list: Any?) -> [[String: Any]] {
            ((list as? [[String: Any]]) ?? []).map { var a = $0; a["uuid"] = nil; a["name"] = nil; return a }
        }
        g["activities"] = strip(g["activities"]); w["activities"] = strip(w["activities"])
        return (g, w)
    }

    @Test(.timeLimit(.minutes(5)))
    func seededHealthKitWorkoutsUploadAsTheFrozenPayload() async throws {
        let share: Set<HKSampleType> = [HKWorkoutType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
                                        HKQuantityType(.workoutEffortScore), HKSeriesType.workoutRoute()]
        try await store.requestAuthorization(toShare: share, read: HKWorkoutUploadTypes.readTypes)

        let fixture = try Self.fixtureWorkouts()
        var seeded: [UUID: [String: Any]] = [:]
        for f in fixture { seeded[try await seed(f).uuid] = f }

        WorkoutSimCapture.reset()
        let suite = "ji.b81.simtest.\(UUID().uuidString)"
        let hub = HubClient(config: ConnectionConfig(baseURL: URL(string: "http://127.0.0.1:8181")!, token: "t"), session: WorkoutSimCapture.session())
        let uploader = HealthKitUploader(store: RealHealthStoreReader(), hub: hub, specs: [], appGroupSuite: suite, timeZone: Self.zone)
        let sent = try await uploader.syncWorkouts()
        #expect(sent >= fixture.count)

        var byUUID: [String: [String: Any]] = [:]
        for body in WorkoutSimCapture.bodies {
            let data = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["data"] as? [String: Any])
            #expect((data["metrics"] as? [Any])?.isEmpty == true)
            for w in (data["workouts"] as? [[String: Any]]) ?? [] { byUUID[w["uuid"] as! String] = w }
        }
        for (uuid, want) in seeded {
            let got = try #require(byUUID[uuid.uuidString], "seeded workout \(want["name"] ?? "?") was not uploaded")
            #expect(Set(got.keys).subtracting(["zone_time"]) == Set(want.keys).subtracting(["zone_time"]), "key set differs for \(want["name"] ?? "?")")
            let (g, w) = normalised(got, like: want)
            #expect(NSDictionary(dictionary: g).isEqual(to: w), "\(want["name"] ?? "?"):\n got \(g)\nwant \(w)")
            print("[B81-SIM] \(want["name"] ?? "?") uuid=\(uuid) avg_hr=\(got["avg_hr_bpm"] ?? "nil") effort_estimated=\(got["effort_estimated"] ?? "nil") zone_time=\(got["zone_time"] != nil ? "present" : "absent") route=\((got["route"] as? [Any])?.count ?? 0) hr=\((got["hr_samples"] as? [Any])?.count ?? 0)")
        }

        // Anchor persisted; the next trigger with nothing new sends nothing (no re-send storm).
        #expect(UserDefaults(suiteName: suite)?.data(forKey: HealthKitUploader.workoutAnchorKey) != nil)
        let posts = WorkoutSimCapture.bodies.count
        for _ in 0..<3 { #expect(try await uploader.syncWorkouts() == 0) }
        #expect(WorkoutSimCapture.bodies.count == posts)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

/// POST capture for the sim test (no hub involved). `@unchecked Sendable`: statics touched only
/// from the serialized test and URLSession's loading thread, one request at a time.
nonisolated final class WorkoutSimCapture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bodies: [Data] = []
    static func reset() { bodies = [] }
    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WorkoutSimCapture.self]
        return URLSession(configuration: c)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buf = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
        }
        Self.bodies.append(data)
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"status":"ok"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

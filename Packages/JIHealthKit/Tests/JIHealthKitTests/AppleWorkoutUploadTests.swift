#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

/// W-B81 A-4 / X-1 (app half): the Apple-workout upload. The frozen contract is
/// `Fixtures/apple_workouts/workouts_payload.json` (a byte copy of HealthTraining's
/// `tests/fixtures/apple_workouts/`, frozen day 0) — the POST body's `workouts` list must equal it.

/// Test double for the workout half of the read seam: serves queued pages, records every anchor /
/// `since` it was asked with, and can throw or suspend to exercise the failure and gate paths.
final class FakeWorkoutUploadReader: HealthStoreWorkoutUploadReading, @unchecked Sendable {
    private let lock = NSLock()
    private var pages: [AppleWorkoutPage] = []
    private var _anchors: [HKQueryAnchor?] = []
    private var _since: [Date?] = []
    var error: Error?
    var delayNanos: UInt64 = 0

    var anchorsSeen: [HKQueryAnchor?] { lock.withLock { _anchors } }
    var sinceSeen: [Date?] { lock.withLock { _since } }
    func enqueue(_ page: AppleWorkoutPage) { lock.withLock { pages.append(page) } }

    func anchoredWorkoutRecords(anchor: HKQueryAnchor?, since: Date?, limit: Int) async throws -> AppleWorkoutPage {
        lock.withLock { _anchors.append(anchor); _since.append(since) }
        if delayNanos > 0 { try await Task.sleep(nanoseconds: delayNanos) }
        if let error { throw error }
        return lock.withLock {
            guard !pages.isEmpty else { return AppleWorkoutPage(records: [], fetchedCount: 0, newAnchor: anchor) }
            return pages.removeFirst()
        }
    }
}

/// This suite's own POST capture (the shared `UploadCapturingURLProtocol` statics race with the
/// other uploader suites, which run in parallel with this one).
final class WorkoutCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestBodies: [Data] = []
    nonisolated(unsafe) static var requestURLs: [URL] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var statusToReturn = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        Self.requestBodies.append(Self.readBody(request))
        if let url = request.url { Self.requestURLs.append(url) }
        let json = "{\"status\":\"ok\",\"days\":1,\"rows_loaded\":1,\"dates\":[]}"
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.statusToReturn, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [WorkoutCapturingURLProtocol.self]
        return URLSession(configuration: c)
    }
    static func reset() { requestBodies = []; requestURLs = []; requestCount = 0; statusToReturn = 200 }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

enum WorkoutFixture {
    static var url: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/apple_workouts/workouts_payload.json")
    }

    static func json() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    static func workouts() throws -> [[String: Any]] {
        let data = try #require(try json()["data"] as? [String: Any])
        return try #require(data["workouts"] as? [[String: Any]])
    }

    static let zone = TimeZone(secondsFromGMT: 2 * 3600)!

    static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f.date(from: s)!
    }

    static func hr(_ pairs: [(String, Double)]) -> [AppleWorkoutRecord.HRSample] {
        pairs.map { .init(ts: date($0.0), bpm: $0.1) }
    }

    /// The three fixture workouts as the HealthKit reader would hand them over (units already
    /// converted, names left for the mapper to derive where Health has none).
    static func records() -> [AppleWorkoutRecord] {
        let indoorRun = AppleWorkoutRecord(
            uuid: UUID(uuidString: "6F1C2A4E-3B7D-4E21-9A10-21A0B0C0D001")!, sport: "running", name: nil, isIndoor: true,
            source: "Apple Watch", start: date("2026-09-21 18:30:00 +0200"), end: date("2026-09-21 19:05:00 +0200"),
            durationS: 2100, distanceM: 6020, kcal: 412, avgHRBpm: 148, maxHRBpm: 165, effortUser: 6.0, effortEstimated: 5.8,
            activities: [
                // A simple Watch workout still carries ONE HKWorkoutActivity — not a segment.
                .init(uuid: UUID(), sport: "running", name: nil, start: date("2026-09-21 18:30:00 +0200"),
                      end: date("2026-09-21 19:05:00 +0200"), durationS: 2100, distanceM: 6020),
            ],
            hrSamples: hr([("2026-09-21 18:30:00 +0200", 102), ("2026-09-21 18:35:00 +0200", 131), ("2026-09-21 18:40:00 +0200", 144),
                           ("2026-09-21 18:45:00 +0200", 149), ("2026-09-21 18:50:00 +0200", 152), ("2026-09-21 18:55:00 +0200", 155),
                           ("2026-09-21 19:00:00 +0200", 158), ("2026-09-21 19:05:00 +0200", 165)]),
            route: [], zoneTime: nil)
        let routeRows: [(String, Double, Double, Double, Double)] = [
            ("2026-09-28 07:12:04 +0200", 53.561, 10.004, 12.0, 2.5), ("2026-09-28 07:17:14 +0200", 53.5631, 10.0057, 13.5, 2.6),
            ("2026-09-28 07:22:24 +0200", 53.5652, 10.0074, 15.0, 3.3), ("2026-09-28 07:27:34 +0200", 53.5673, 10.0091, 16.5, 3.4),
            ("2026-09-28 07:32:44 +0200", 53.5694, 10.0108, 12.0, 3.3), ("2026-09-28 07:37:54 +0200", 53.5715, 10.004, 13.5, 3.5),
            ("2026-09-28 07:43:04 +0200", 53.5736, 10.0057, 15.0, 3.4), ("2026-09-28 07:48:14 +0200", 53.5757, 10.0074, 16.5, 3.3),
            ("2026-09-28 07:53:24 +0200", 53.5778, 10.0091, 12.0, 2.4), ("2026-09-28 07:58:34 +0200", 53.5799, 10.0108, 13.5, 2.1),
        ]
        let outdoorRun = AppleWorkoutRecord(
            uuid: UUID(uuidString: "9B3E7D10-5A2C-4F88-8E61-28A0B0C0D002")!, sport: "running", name: nil, isIndoor: false,
            source: "Apple Watch", start: date("2026-09-28 07:12:04 +0200"), end: date("2026-09-28 07:58:34 +0200"),
            durationS: 2790, distanceM: 8210, kcal: 598, avgHRBpm: 152, maxHRBpm: 178, effortUser: 7.0, effortEstimated: 6.9,
            activities: [
                .init(uuid: UUID(uuidString: "9B3E7D10-5A2C-4F88-8E61-28A0B0C0D0A1")!, sport: "running", name: "Warm-up",
                      start: date("2026-09-28 07:12:04 +0200"), end: date("2026-09-28 07:22:04 +0200"), durationS: 600, distanceM: 1520),
                .init(uuid: UUID(uuidString: "9B3E7D10-5A2C-4F88-8E61-28A0B0C0D0A2")!, sport: "running", name: "Work",
                      start: date("2026-09-28 07:22:04 +0200"), end: date("2026-09-28 07:52:04 +0200"), durationS: 1800, distanceM: 5900),
                .init(uuid: UUID(uuidString: "9B3E7D10-5A2C-4F88-8E61-28A0B0C0D0A3")!, sport: "running", name: "Cool-down",
                      start: date("2026-09-28 07:52:04 +0200"), end: date("2026-09-28 07:58:34 +0200"), durationS: 390, distanceM: 790),
            ],
            hrSamples: hr([("2026-09-28 07:12:04 +0200", 98), ("2026-09-28 07:17:14 +0200", 128), ("2026-09-28 07:22:24 +0200", 139),
                           ("2026-09-28 07:27:34 +0200", 150), ("2026-09-28 07:32:44 +0200", 158), ("2026-09-28 07:37:54 +0200", 163),
                           ("2026-09-28 07:43:04 +0200", 170), ("2026-09-28 07:48:14 +0200", 178), ("2026-09-28 07:53:24 +0200", 149),
                           ("2026-09-28 07:58:34 +0200", 132)]),
            route: routeRows.map { .init(ts: date($0.0), lat: $0.1, lon: $0.2, elevationM: $0.3, speedMps: $0.4, hAccuracyM: 4.0) },
            zoneTime: [
                .init(zone: 1, lowerBpm: 0, upperBpm: 125, seconds: 240), .init(zone: 2, lowerBpm: 125, upperBpm: 140, seconds: 520),
                .init(zone: 3, lowerBpm: 140, upperBpm: 155, seconds: 910), .init(zone: 4, lowerBpm: 155, upperBpm: 170, seconds: 880),
                .init(zone: 5, lowerBpm: 170, upperBpm: nil, seconds: 240),
            ])
        let indoorCycle = AppleWorkoutRecord(
            uuid: UUID(uuidString: "2D8A4C66-1E9F-4B35-B7C2-25A0B0C0D003")!, sport: "cycling", name: nil, isIndoor: true,
            source: "Apple Watch", start: date("2026-09-25 17:45:00 +0200"), end: date("2026-09-25 18:30:00 +0200"),
            durationS: 2700, distanceM: nil, kcal: 380, avgHRBpm: 131, maxHRBpm: 158, effortUser: nil, effortEstimated: 5.3,
            activities: [],
            hrSamples: hr([("2026-09-25 17:45:00 +0200", 95), ("2026-09-25 17:52:30 +0200", 118), ("2026-09-25 18:00:00 +0200", 129),
                           ("2026-09-25 18:07:30 +0200", 134), ("2026-09-25 18:15:00 +0200", 138), ("2026-09-25 18:22:30 +0200", 158),
                           ("2026-09-25 18:30:00 +0200", 126)]),
            route: [], zoneTime: nil)
        return [indoorRun, outdoorRun, indoorCycle]
    }
}

@Suite(.serialized) struct AppleWorkoutUploadTests {
    private func hub() -> HubClient {
        HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8181")!, token: "t0k"), session: WorkoutCapturingURLProtocol.session())
    }

    private func defaults() -> UserDefaults {
        let name = "ji.b81.workouts.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func uploader(_ reader: FakeWorkoutUploadReader, defaults: UserDefaults? = nil) -> HealthKitUploader {
        HealthKitUploader(store: FakeHealthStoreReader(), hub: hub(), specs: [], defaults: defaults, workouts: reader, timeZone: WorkoutFixture.zone)
    }

    private func body(_ i: Int) throws -> [String: Any] {
        let obj = try #require(try JSONSerialization.jsonObject(with: WorkoutCapturingURLProtocol.requestBodies[i]) as? [String: Any])
        return try #require(obj["data"] as? [String: Any])
    }

    private static let now = WorkoutFixture.date("2026-09-28 17:00:00 +0200")

    // MARK: - Backfill window (Toby 2026-09-28: a Settings choice; 30 days by default)

    @Test func theChosenWindowSetsTheFirstSyncStart() async throws {
        for (choice, days) in [(WorkoutBackfill.days90, 90.0), (.days120, 120), (.year, 365)] {
            let d = defaults()
            WorkoutBackfill.set(choice, defaults: d)
            let reader = FakeWorkoutUploadReader()
            _ = try await uploader(reader, defaults: d).syncWorkouts(now: Self.now)
            let since = try #require(reader.sinceSeen.first ?? nil)
            #expect(abs(since.timeIntervalSince(Self.now) + days * 86_400) < 1)
        }
        let d = defaults()
        WorkoutBackfill.set(.all, defaults: d)
        let reader = FakeWorkoutUploadReader()
        _ = try await uploader(reader, defaults: d).syncWorkouts(now: Self.now)
        #expect(reader.sinceSeen.first! == nil) // everything HealthKit holds
    }

    @Test func wideningTheWindowResendsFromTheNewStartNarrowingKeepsTheAnchor() async throws {
        WorkoutCapturingURLProtocol.reset()
        let d = defaults()
        let first = FakeWorkoutUploadReader()
        first.enqueue(AppleWorkoutPage(records: [WorkoutFixture.records()[0]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 3)))
        _ = try await uploader(first, defaults: d).syncWorkouts(now: Self.now)
        #expect(d.data(forKey: HealthKitUploader.workoutAnchorKey) != nil)

        WorkoutBackfill.set(.year, defaults: d)           // wider → anchor cleared, re-send (idempotent by UUID)
        #expect(d.data(forKey: HealthKitUploader.workoutAnchorKey) == nil)
        let second = FakeWorkoutUploadReader()
        second.enqueue(AppleWorkoutPage(records: [WorkoutFixture.records()[0]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 4)))
        _ = try await uploader(second, defaults: d).syncWorkouts(now: Self.now)
        let since = try #require(second.sinceSeen.first ?? nil)
        #expect(abs(since.timeIntervalSince(Self.now) + 365 * 86_400) < 1)

        WorkoutBackfill.set(.days30, defaults: d)         // narrower → nothing deleted, anchor kept
        #expect(d.data(forKey: HealthKitUploader.workoutAnchorKey) != nil)
        #expect(WorkoutBackfill.current(d) == .days30)
    }

    // MARK: - A-4: the POST body is the frozen contract

    @Test func postBodyMatchesTheFrozenFixture() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: WorkoutFixture.records(), fetchedCount: 3, newAnchor: HKQueryAnchor(fromValue: 1)))
        let sent = try await uploader(reader, defaults: defaults()).syncWorkouts(now: Self.now)
        #expect(sent == 3)
        #expect(WorkoutCapturingURLProtocol.requestCount == 1)
        let data = try body(0)
        let workouts = try #require(data["workouts"] as? [[String: Any]])
        let expected = try WorkoutFixture.workouts()
        #expect(workouts.count == expected.count)
        for (got, want) in zip(workouts, expected) {
            #expect(NSDictionary(dictionary: got).isEqual(to: want), "workout \(want["uuid"] ?? "?") differs:\n got \(got)\nwant \(want)")
            #expect(Set(got.keys) == Set(want.keys), "key set drifted for \(want["uuid"] ?? "?")")
        }
        // A workout-only POST carries no metric points (never a stale or empty metric overwrite).
        #expect((data["metrics"] as? [Any])?.isEmpty == true)
    }

    @Test func postGoesToTheExistingAppleHealthIngestPath() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: [WorkoutFixture.records()[0]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 1)))
        _ = try await uploader(reader, defaults: defaults()).syncWorkouts(now: Self.now)
        #expect(WorkoutCapturingURLProtocol.requestURLs.last?.path == "/api/v1/ingest/apple-health")
    }

    // MARK: - Anchor, backfill, no re-send storm

    @Test func firstSyncBackfillsTheDefault30DaysThenResumesFromThePersistedAnchor() async throws {
        WorkoutCapturingURLProtocol.reset()
        let d = defaults()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: [WorkoutFixture.records()[0]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 7)))
        _ = try await uploader(reader, defaults: d).syncWorkouts(now: Self.now)

        let since = try #require(reader.sinceSeen.first ?? nil)
        #expect(abs(since.timeIntervalSince(Self.now) + 30 * 86_400) < 1)
        #expect(reader.anchorsSeen.first! == nil)
        #expect(d.data(forKey: HealthKitUploader.workoutAnchorKey) != nil)

        // A NEW uploader instance (killed + relaunched app) resumes from the stored anchor.
        let second = FakeWorkoutUploadReader()
        let sent = try await uploader(second, defaults: d).syncWorkouts(now: Self.now)
        #expect(sent == 0)
        #expect(second.anchorsSeen.first! == HKQueryAnchor(fromValue: 7))
        #expect(second.sinceSeen.first! == nil)
        #expect(WorkoutCapturingURLProtocol.requestCount == 1) // nothing new → no second POST
    }

    @Test func repeatedObserverFiresWithNothingNewNeverPost() async throws {
        WorkoutCapturingURLProtocol.reset()
        let d = defaults()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: WorkoutFixture.records(), fetchedCount: 3, newAnchor: HKQueryAnchor(fromValue: 2)))
        let up = uploader(reader, defaults: d)
        for _ in 0..<5 { _ = try await up.syncWorkouts(now: Self.now) }
        #expect(WorkoutCapturingURLProtocol.requestCount == 1)
    }

    @Test func concurrentTriggersRunOneSyncAtATime() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        reader.delayNanos = 100_000_000
        reader.enqueue(AppleWorkoutPage(records: WorkoutFixture.records(), fetchedCount: 3, newAnchor: HKQueryAnchor(fromValue: 3)))
        let up = uploader(reader, defaults: defaults())
        async let a = up.syncWorkouts(now: Self.now)
        async let b = up.syncWorkouts(now: Self.now)
        let (x, y) = try await (a, b)
        #expect(x + y == 3)
        #expect(WorkoutCapturingURLProtocol.requestCount == 1)
    }

    @Test func largePagesArePostedInBoundedBatches() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        let base = WorkoutFixture.records()[0]
        let many = (0..<(HealthKitUploader.workoutBatchSize + 2)).map { i -> AppleWorkoutRecord in
            var r = base; r.uuid = UUID(); r.start = base.start.addingTimeInterval(Double(i) * 86_400); r.end = base.end.addingTimeInterval(Double(i) * 86_400); return r
        }
        reader.enqueue(AppleWorkoutPage(records: many, fetchedCount: many.count, newAnchor: HKQueryAnchor(fromValue: 4)))
        let sent = try await uploader(reader, defaults: defaults()).syncWorkouts(now: Self.now)
        #expect(sent == many.count)
        #expect(WorkoutCapturingURLProtocol.requestCount == 2)
    }

    @Test func aFullPageLoopsForTheNextOne() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        let r = WorkoutFixture.records()
        reader.enqueue(AppleWorkoutPage(records: [r[0]], fetchedCount: HealthKitUploader.workoutPageLimit, newAnchor: HKQueryAnchor(fromValue: 5)))
        reader.enqueue(AppleWorkoutPage(records: [r[1]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 6)))
        let sent = try await uploader(reader, defaults: defaults()).syncWorkouts(now: Self.now)
        #expect(sent == 2)
        #expect(reader.anchorsSeen.count == 2)
        #expect(reader.anchorsSeen[1] == HKQueryAnchor(fromValue: 5))
    }

    // MARK: - X-1 (app half): an empty or partial upload never deletes or overwrites stored workouts

    @Test func emptyFirstPageNeverPosts() async throws {
        WorkoutCapturingURLProtocol.reset()
        let sent = try await uploader(FakeWorkoutUploadReader(), defaults: defaults()).syncWorkouts(now: Self.now)
        #expect(sent == 0)
        #expect(WorkoutCapturingURLProtocol.requestCount == 0)
    }

    @Test func pageOfOnlyFilteredOrDeletedWorkoutsNeverPosts() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        // HealthKit returned 4 objects (e.g. this app's own Garmin backloads), none survived the filter.
        reader.enqueue(AppleWorkoutPage(records: [], fetchedCount: 4, newAnchor: HKQueryAnchor(fromValue: 9)))
        let d = defaults()
        let sent = try await uploader(reader, defaults: d).syncWorkouts(now: Self.now)
        #expect(sent == 0)
        #expect(WorkoutCapturingURLProtocol.requestCount == 0)
        #expect(d.data(forKey: HealthKitUploader.workoutAnchorKey) != nil) // but the anchor moves on
    }

    @Test func metricUploadsNeverCarryAWorkoutsKey() throws {
        let env = HAEEnvelope(metrics: [HAEMetric(name: "step_count", units: "count", data: [HAEDataPoint(date: "2026-09-28 00:00:00 +0200", qty: 1)])])
        let obj = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(env)) as? [String: Any])
        let data = try #require(obj["data"] as? [String: Any])
        #expect(data["workouts"] == nil) // absent, never `[]` — the hub must not read "no workouts"
    }

    @Test func failedPostKeepsTheAnchorSoTheBatchIsRetriedWhole() async throws {
        WorkoutCapturingURLProtocol.reset()
        WorkoutCapturingURLProtocol.statusToReturn = 500
        let d = defaults()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: WorkoutFixture.records(), fetchedCount: 3, newAnchor: HKQueryAnchor(fromValue: 11)))
        await #expect(throws: (any Error).self) { try await uploader(reader, defaults: d).syncWorkouts(now: Self.now) }
        #expect(d.data(forKey: HealthKitUploader.workoutAnchorKey) == nil)
        #expect(d.string(forKey: HealthKitUploader.lastSuccessKey) == nil)
        WorkoutCapturingURLProtocol.statusToReturn = 200
    }

    @Test func aReadFailureSendsNothingPartial() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        reader.error = HKError(.errorDatabaseInaccessible)
        let d = defaults()
        await #expect(throws: (any Error).self) { try await uploader(reader, defaults: d).syncWorkouts(now: Self.now) }
        #expect(WorkoutCapturingURLProtocol.requestCount == 0)
        #expect(d.data(forKey: HealthKitUploader.workoutAnchorKey) == nil)
    }

    @Test func successStampsTheArrivalKeys() async throws {
        WorkoutCapturingURLProtocol.reset()
        let d = defaults()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: [WorkoutFixture.records()[2]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 1)))
        _ = try await uploader(reader, defaults: d).syncWorkouts(now: Self.now)
        #expect(d.string(forKey: HealthKitUploader.lastSuccessKey) != nil)
        #expect(d.string(forKey: HealthKitArrival.key(for: HKWorkoutType.workoutType())) != nil)
    }

    // MARK: - Wiring into the existing uploader surface

    @Test func syncAllIncludesWorkouts() async throws {
        WorkoutCapturingURLProtocol.reset()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: [WorkoutFixture.records()[0]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 1)))
        let results = await uploader(reader, defaults: defaults()).syncAll()
        let r = try #require(results[HealthKitUploader.workoutsResultKey])
        #expect((try? r.get()) == 1)
    }

    @Test func backgroundDeliveryObservesWorkoutsAndAnObserverFireUploads() async throws {
        WorkoutCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let reader = FakeWorkoutUploadReader()
        reader.enqueue(AppleWorkoutPage(records: [WorkoutFixture.records()[1]], fetchedCount: 1, newAnchor: HKQueryAnchor(fromValue: 1)))
        let up = HealthKitUploader(store: store, hub: hub(), specs: [], defaults: defaults(), workouts: reader, timeZone: WorkoutFixture.zone)
        _ = try await up.startBackgroundDelivery()
        let id = HKWorkoutType.workoutType().identifier
        #expect(store.backgroundDeliveryEnabled[id] != nil)
        let handler = try #require(store.observerHandlers[id])
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in handler { c.resume() } }
        #expect(WorkoutCapturingURLProtocol.requestCount == 1)
    }

    @Test func authorizationAsksForWhatTheWorkoutReaderNeeds() async throws {
        let store = FakeHealthStoreReader()
        let up = HealthKitUploader(store: store, hub: hub(), specs: [], defaults: defaults(), workouts: FakeWorkoutUploadReader(), timeZone: WorkoutFixture.zone)
        try await up.requestAuthorization()
        for type in HKWorkoutUploadTypes.readTypes { #expect(store.requestedReadTypes.contains(type), "missing \(type)") }
    }

    @Test func noWorkoutReaderMeansNoWorkoutWork() async throws {
        WorkoutCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let up = HealthKitUploader(store: store, hub: hub(), specs: [], defaults: defaults())
        let results = await up.syncAll()
        #expect(results[HealthKitUploader.workoutsResultKey] == nil)
        _ = try await up.startBackgroundDelivery()
        #expect(store.backgroundDeliveryEnabled[HKWorkoutType.workoutType().identifier] == nil)
    }
}

/// The pure mapping pieces the real HealthKit reader relies on.
@Suite struct AppleWorkoutMappingTests {
    @Test func sportIsLowerSnakeCase() {
        #expect(AppleWorkoutSport.name(.running) == "running")
        #expect(AppleWorkoutSport.name(.cycling) == "cycling")
        #expect(AppleWorkoutSport.name(.walking) == "walking")
        #expect(AppleWorkoutSport.name(.traditionalStrengthTraining) == "traditional_strength_training")
        #expect(AppleWorkoutSport.name(.functionalStrengthTraining) == "functional_strength_training")
        #expect(AppleWorkoutSport.name(.highIntensityIntervalTraining) == "high_intensity_interval_training")
    }

    @Test func derivedNamesFollowIndoorAndSport() {
        #expect(AppleWorkoutMapper.derivedName(sport: "running", isIndoor: true) == "Indoor Run")
        #expect(AppleWorkoutMapper.derivedName(sport: "running", isIndoor: false) == "Outdoor Run")
        #expect(AppleWorkoutMapper.derivedName(sport: "cycling", isIndoor: true) == "Indoor Cycle")
        #expect(AppleWorkoutMapper.derivedName(sport: "walking", isIndoor: nil) == "Walk")
        #expect(AppleWorkoutMapper.derivedName(sport: "traditional_strength_training", isIndoor: nil) == "Traditional Strength Training")
    }

    /// This app writes the hub's Garmin workouts into Health (`workout:<id>` sync ids). Sending them
    /// back as Apple workouts would count every Garmin session twice — they are filtered out.
    @Test func hubBackloadsAreNotApple() {
        #expect(AppleWorkoutFilter.isHubBackload(fromThisApp: true, syncIdentifier: "workout:21430001234"))
        #expect(!AppleWorkoutFilter.isHubBackload(fromThisApp: false, syncIdentifier: "workout:21430001234"))
        #expect(!AppleWorkoutFilter.isHubBackload(fromThisApp: true, syncIdentifier: nil))
        #expect(!AppleWorkoutFilter.isHubBackload(fromThisApp: false, syncIdentifier: nil))
    }

    @Test func zoneDurationsAreNumberedFromOneInIndexOrder() {
        let zones = AppleWorkoutMapper.zoneTimes([
            (index: 2, lower: 140, upper: 155, seconds: 910.4), (index: 0, lower: nil, upper: 125, seconds: 240),
            (index: 1, lower: 125, upper: 140, seconds: 519.6),
        ])
        #expect(zones == [
            .init(zone: 1, lowerBpm: nil, upperBpm: 125, seconds: 240),
            .init(zone: 2, lowerBpm: 125, upperBpm: 140, seconds: 520),
            .init(zone: 3, lowerBpm: 140, upperBpm: 155, seconds: 910),
        ])
        #expect(AppleWorkoutMapper.zoneTimes([]) == nil)
    }

    @Test func aSingleActivityIsNotASegment() throws {
        let r = WorkoutFixture.records()[0]
        let w = AppleWorkoutMapper.payload(r, timeZone: WorkoutFixture.zone)
        #expect(!w.isParent && w.segmentCount == 0 && w.activities.isEmpty)
        let parent = AppleWorkoutMapper.payload(WorkoutFixture.records()[1], timeZone: WorkoutFixture.zone)
        #expect(parent.isParent && parent.segmentCount == 3 && parent.activities.count == 3)
    }

    @Test func hrSamplesAndRouteAreSortedByTime() {
        var r = WorkoutFixture.records()[1]
        r.hrSamples.reverse(); r.route.reverse()
        let w = AppleWorkoutMapper.payload(r, timeZone: WorkoutFixture.zone)
        #expect(w.hrSamples.first?.ts == "2026-09-28 07:12:04 +0200")
        #expect(w.route.first?.ts == "2026-09-28 07:12:04 +0200")
    }
}
#endif

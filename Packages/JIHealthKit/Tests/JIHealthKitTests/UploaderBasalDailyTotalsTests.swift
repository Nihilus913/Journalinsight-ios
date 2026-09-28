#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

/// WD-6 (DEV-13): basal energy leaves the phone as HealthKit's source-merged DAILY totals (the
/// statistics query), never as raw samples — overlapping devices and samples straddling midnight
/// no longer double or split a day. The hub sums a day's increment deliveries, so each POST
/// carries the change since the last delivered total (a ledger per day); the sum on the hub is the
/// HealthKit total. Own POST-capturing stub (private statics, `.serialized`), same reason as
/// `UploaderRMSSDTests`.
final class BasalUploadCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestBodies: [Data] = []
    nonisolated(unsafe) static var statusToReturn = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestBodies.append(Self.readBody(request))
        let json = "{\"status\":\"ok\",\"days\":1,\"rows_loaded\":1,\"dates\":[]}"
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.statusToReturn, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [BasalUploadCapturingURLProtocol.self]
        return URLSession(configuration: c)
    }
    static func reset() { requestBodies = []; statusToReturn = 200 }

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

/// Statistics double: day start → source-merged total; records every queried range.
final class FakeUploadStatistics: HealthStoreUploadStatistics, @unchecked Sendable {
    var totals: [Date: Double] = [:]
    private(set) var ranges: [DateInterval] = []
    func dailySumsExcludingOwnWrites(for type: HKQuantityType, unit: HKUnit, start: Date, end: Date, calendar: Calendar) async throws -> [Date: Double] {
        ranges.append(DateInterval(start: start, end: end))
        return totals.filter { $0.key >= start && $0.key < end }
    }
}

@Suite(.serialized) struct UploaderBasalDailyTotalsTests {
    private let basalType = HKQuantityType(.basalEnergyBurned)
    private var zurich: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Zurich")!; return c
    }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        zurich.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    private func midnight(_ day: Int) -> Date { at(day, 0) }
    private var now: Date { at(27, 10) }

    private func basal(_ kcal: Double, _ start: Date, minutes: Double = 30) -> HKQuantitySample {
        HKQuantitySample(type: basalType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: start.addingTimeInterval(minutes * 60))
    }

    private var spec: HKMetricSpec {
        HKMetricSpec(sampleType: basalType, metricName: "basal_energy_burned", units: "kcal", backgroundFrequency: .hourly,
                     mapSamples: HKSampleMapping.perSample(unit: .kilocalorie()))
    }

    private func uploader(_ store: FakeHealthStoreReader, _ stats: FakeUploadStatistics?, _ defaults: UserDefaults) -> HealthKitUploader {
        HealthKitUploader(store: store, hub: HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"), session: BasalUploadCapturingURLProtocol.session()),
                          specs: [spec], defaults: defaults, statistics: stats, calendar: zurich)
    }

    private func postedPoints(_ index: Int) throws -> [[String: Any]] {
        try #require(BasalUploadCapturingURLProtocol.requestBodies.indices.contains(index))
        let obj = try #require(try JSONSerialization.jsonObject(with: BasalUploadCapturingURLProtocol.requestBodies[index]) as? [String: Any])
        let metrics = try #require((obj["data"] as? [String: Any])?["metrics"] as? [[String: Any]])
        #expect(metrics.count == 1)
        #expect(metrics[0]["name"] as? String == "basal_energy_burned")
        return try #require(metrics[0]["data"] as? [[String: Any]])
    }

    private func page(_ samples: [HKSample], _ anchor: Int) -> HKAnchoredPage {
        HKAnchoredPage(samples: samples, deletedObjectIDs: [], newAnchor: HKQueryAnchor(fromValue: anchor))
    }

    @Test func basalSpecUploadsDailyTotalsOtherSpecsDoNot() {
        #expect(spec.dailyTotalUnit == .kilocalorie())
        let steps = HKMetricSpec(sampleType: HKQuantityType(.stepCount), metricName: HAEMetricName.stepCount, units: "count",
                                 backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))
        #expect(steps.dailyTotalUnit == nil)
    }

    @Test func firstSyncSendsOneDeduplicatedTotalPerTouchedDayNotRawSamples() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        // Five raw samples (two devices overlapping on the 25th, one straddling midnight 25→26).
        store.enqueue(page([basal(40, at(25, 8)), basal(40, at(25, 8)), basal(35, at(25, 23, 45)), basal(30, at(26, 9)), basal(30, at(26, 10))], 1), for: basalType)
        let stats = FakeUploadStatistics()
        stats.totals = [midnight(25): 1901.44, midnight(26): 1850]
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        let count = try await uploader(store, stats, defaults).sync(spec, now: now)
        #expect(count == 2)
        let points = try postedPoints(0)
        #expect(points.map { $0["date"] as? String } == ["2026-09-25 00:00:00 +0200", "2026-09-26 00:00:00 +0200"])
        #expect(points.map { $0["qty"] as? Double } == [1901.4, 1850])
        #expect(defaults.string(forKey: HealthKitArrival.key(for: basalType)) != nil)
    }

    @Test func laterSyncSendsOnlyTheChangeSinceTheDeliveredTotal() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        store.enqueue(page([basal(30, at(26, 9))], 1), for: basalType)
        stats.totals = [midnight(26): 1800]
        _ = try await uploader(store, stats, defaults).sync(spec, now: now)
        // A new sample later that day: HealthKit's total rises to 1950 → the hub gets +150, so its
        // sum over deliveries is 1950 — never 1800 + 1950.
        store.enqueue(page([basal(30, at(26, 20))], 2), for: basalType)
        stats.totals = [midnight(26): 1950]
        _ = try await uploader(store, stats, defaults).sync(spec, now: now)
        #expect(BasalUploadCapturingURLProtocol.requestBodies.count == 2)
        #expect(try postedPoints(1).map { $0["qty"] as? Double } == [150])
    }

    @Test func unchangedTotalPostsNothingButAdvancesTheAnchor() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        store.enqueue(page([basal(30, at(26, 9))], 1), for: basalType)
        stats.totals = [midnight(26): 1800]
        _ = try await uploader(store, stats, defaults).sync(spec, now: now)
        // A sample from our own backload (excluded by the statistics query) leaves the total as is.
        store.enqueue(page([basal(30, at(26, 11))], 2), for: basalType)
        let count = try await uploader(store, stats, defaults).sync(spec, now: now)
        #expect(count == 0)
        #expect(BasalUploadCapturingURLProtocol.requestBodies.count == 1)
        #expect(store.anchorsSeen[basalType.identifier]?.last != nil)
        // Third run reads from anchor 2 (advanced), not anchor 1.
        _ = try await uploader(store, stats, defaults).sync(spec, now: now)
        let lastAnchor = try #require(store.anchorsSeen[basalType.identifier]?.last ?? nil)
        #expect(lastAnchor == HKQueryAnchor(fromValue: 2))
    }

    @Test func aDayWithoutAHealthKitTotalIsNeverSentAsZero() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics() // no totals at all
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        store.enqueue(page([basal(30, at(26, 9))], 1), for: basalType)
        let count = try await uploader(store, stats, defaults).sync(spec, now: now)
        #expect(count == 0)
        #expect(BasalUploadCapturingURLProtocol.requestBodies.isEmpty)
    }

    // MARK: - F6-10 (device 2026-09-28): 09-27 stuck at 921.9, 09-28 never sent

    /// Watch-like basal stream: one sample per hour, `kcal` each, for hours `[from, to)` of `day`.
    private func hourly(_ day: Int, _ from: Int, _ to: Int, kcal: Double) -> [HKSample] {
        (from..<to).map { basal(kcal, at(day, $0), minutes: 60) }
    }

    private func archived(_ value: Int) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: HKQueryAnchor(fromValue: value), requiringSecureCoding: true)
    }

    @Test func replay0927TheRestOfTheDayFollowsThe1219Total() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        // 12:19 — the morning's samples; HealthKit's total so far is 921.9.
        store.enqueue(page(hourly(27, 0, 12, kcal: 76.825), 1), for: basalType)
        stats.totals = [midnight(27): 921.9]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(27, 12, 19))
        #expect(try postedPoints(0).map { $0["qty"] as? Double } == [921.9])
        // 09-28 05:30 — the afternoon/evening of the 27th and the night of the 28th arrive.
        store.enqueue(page(hourly(27, 12, 24, kcal: 76.825) + hourly(28, 0, 5, kcal: 76.82), 2), for: basalType)
        stats.totals = [midnight(27): 1843.8, midnight(28): 384.1]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(28, 5, 30))
        let points = try postedPoints(1)
        #expect(points.map { $0["date"] as? String } == ["2026-09-27 00:00:00 +0200", "2026-09-28 00:00:00 +0200"])
        #expect(points.map { $0["qty"] as? Double } == [921.9, 384.1])
    }

    @Test func aFinishedDaysFinalTotalIsSentEvenWhenNoNewSampleStartsThatDay() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        store.enqueue(page(hourly(27, 0, 23, kcal: 80), 1), for: basalType)
        stats.totals = [midnight(27): 1840]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(27, 23, 10))
        // After midnight only samples of the 28th are new, but HealthKit's final total for the
        // 27th grew (a late-written sample merged by the statistics query): the 27th is topped up.
        store.enqueue(page(hourly(28, 0, 2, kcal: 80), 2), for: basalType)
        stats.totals = [midnight(27): 1920, midnight(28): 160]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(28, 2, 30))
        #expect(try postedPoints(1).map { $0["qty"] as? Double } == [80, 160])
        #expect((defaults.dictionary(forKey: HealthKitUploader.dailyLedgerKey(spec)) as? [String: Double])?["2026-09-27"] == 1920)
    }

    @Test func firstRunAfterTheSwitchSendsYesterdaysRemainderAndTodaysTotal() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        // The raw-sample path sent the 27th's samples through 12:00 (921.9 on the hub) and holds
        // anchor 7; everything after it is new to the hub.
        defaults.set(try archived(7), forKey: spec.anchorKey)
        store.enqueue(page(hourly(27, 12, 24, kcal: 76.825) + hourly(28, 0, 5, kcal: 76.82), 8), for: basalType)
        // The switch reads the raw samples of the touched days (what the hub summed) once.
        store.enqueue(page(hourly(27, 0, 24, kcal: 76.825) + hourly(28, 0, 5, kcal: 76.82), 99), for: basalType)
        stats.totals = [midnight(26): 1900, midnight(27): 1843.8, midnight(28): 384.1]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(28, 5, 30))
        let points = try postedPoints(0)
        #expect(points.map { $0["date"] as? String } == ["2026-09-27 00:00:00 +0200", "2026-09-28 00:00:00 +0200"])
        #expect(points.map { $0["qty"] as? Double } == [921.9, 384.1])
        // The persisted anchor is the change feed's (8), not the one-off raw read's.
        let stored = try #require(defaults.data(forKey: spec.anchorKey))
        #expect(try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: stored) == HKQueryAnchor(fromValue: 8))
        // Afterwards: plain deltas.
        store.enqueue(page(hourly(28, 5, 6, kcal: 76.9), 9), for: basalType)
        stats.totals = [midnight(27): 1843.8, midnight(28): 461]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(28, 6, 30))
        #expect(try postedPoints(1).map { $0["qty"] as? Double } == [76.9])
    }

    @Test func switchWithNothingNewSendsNothingButTracksTodayFromThen() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        defaults.set(try archived(7), forKey: spec.anchorKey)
        store.enqueue(page([], 7), for: basalType)                         // change feed: nothing new
        store.enqueue(page(hourly(28, 0, 5, kcal: 80), 99), for: basalType) // raw read of today
        stats.totals = [midnight(27): 1900, midnight(28): 400]
        let count = try await uploader(store, stats, defaults).sync(spec, now: at(28, 5, 30))
        #expect(count == 0)
        #expect(BasalUploadCapturingURLProtocol.requestBodies.isEmpty)
        store.enqueue(page(hourly(28, 5, 6, kcal: 80), 8), for: basalType)
        stats.totals = [midnight(27): 1900, midnight(28): 480]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(28, 6, 30))
        #expect(try postedPoints(0).map { $0["date"] as? String } == ["2026-09-28 00:00:00 +0200"])
        #expect(try postedPoints(0).map { $0["qty"] as? Double } == [80])
    }

    @Test func deviceStateFromSwiftFix5SendsTheSwitchDaysTotal() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        // swift-fix5's first run (09-28 05:25) found the raw anchor, stored "start 09-29" and moved
        // the anchor past the 28th's samples without sending them. The fixed build must send the
        // 28th's total (nothing raw was sent for it) and keep going with deltas.
        defaults.set(try archived(20), forKey: spec.anchorKey)
        defaults.set("2026-09-29", forKey: HealthKitUploader.dailyStartKey(spec))
        store.enqueue(page(hourly(28, 7, 8, kcal: 80), 21), for: basalType)
        stats.totals = [midnight(27): 1843.8, midnight(28): 700]
        _ = try await uploader(store, stats, defaults).sync(spec, now: at(28, 8, 30))
        #expect(try postedPoints(0).map { $0["date"] as? String } == ["2026-09-28 00:00:00 +0200"])
        #expect(try postedPoints(0).map { $0["qty"] as? Double } == [700])
    }

    @Test func failedPostKeepsTheLedgerAndTheAnchor() async throws {
        BasalUploadCapturingURLProtocol.reset()
        BasalUploadCapturingURLProtocol.statusToReturn = 500
        defer { BasalUploadCapturingURLProtocol.reset() }
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        store.enqueue(page([basal(30, at(26, 9))], 1), for: basalType)
        stats.totals = [midnight(26): 1800]
        await #expect(throws: (any Error).self) { try await uploader(store, stats, defaults).sync(spec, now: now) }
        #expect(defaults.data(forKey: spec.anchorKey) == nil)
        // Retry succeeds and sends the full total (nothing was recorded as delivered).
        BasalUploadCapturingURLProtocol.statusToReturn = 200
        store.enqueue(page([basal(30, at(26, 9))], 1), for: basalType)
        _ = try await uploader(store, stats, defaults).sync(spec, now: now)
        #expect(try postedPoints(1).map { $0["qty"] as? Double } == [1800])
    }

    @Test func withoutAStatisticsStoreBasalFallsBackToRawSamples() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        store.enqueue(page([basal(30, at(26, 9)), basal(20, at(26, 10))], 1), for: basalType)
        let count = try await uploader(store, nil, defaults).sync(spec, now: now)
        #expect(count == 2)
        #expect(try postedPoints(0).map { $0["qty"] as? Double } == [30, 20])
    }
}
#endif

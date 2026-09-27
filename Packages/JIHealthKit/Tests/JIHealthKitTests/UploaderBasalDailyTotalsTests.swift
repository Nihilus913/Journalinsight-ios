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

    @Test func switchingFromRawSamplesStartsTomorrowSoNoDayIsCountedTwice() async throws {
        BasalUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stats = FakeUploadStatistics()
        let defaults = try #require(UserDefaults(suiteName: "basal.\(UUID())"))
        // The raw-sample path already ran: an anchor exists, the hub holds raw sums through today.
        let old = try NSKeyedArchiver.archivedData(withRootObject: HKQueryAnchor(fromValue: 7), requiringSecureCoding: true)
        defaults.set(old, forKey: spec.anchorKey)
        store.enqueue(page([basal(30, at(26, 9)), basal(30, at(27, 9))], 8), for: basalType)
        stats.totals = [midnight(26): 1800, midnight(27): 700]
        let count = try await uploader(store, stats, defaults).sync(spec, now: now)
        #expect(count == 0)
        #expect(BasalUploadCapturingURLProtocol.requestBodies.isEmpty)
        // Next day: the 28th is on the new path.
        let tomorrow = at(28, 10)
        store.enqueue(page([basal(30, at(28, 9))], 9), for: basalType)
        stats.totals = [midnight(27): 1900, midnight(28): 650]
        _ = try await uploader(store, stats, defaults).sync(spec, now: tomorrow)
        #expect(try postedPoints(0).map { $0["date"] as? String } == ["2026-09-28 00:00:00 +0200"])
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

#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

/// B5 L2 — native-RMSSD upload wiring. Every test runs against a fake store + POST-capturing
/// stub; the RMSSD `HKSampleType` comes from `HKReadKind.hrvRMSSD` (never re-resolved here).
/// Tests that need a real RMSSD sample skip themselves on a host whose SDK lacks the type.
/// Own POST-capturing stub, deliberately NOT `RMSSDUploadCapturingURLProtocol`: Swift Testing runs
/// suites in parallel, and sharing that class's `nonisolated(unsafe)` statics across two suites
/// makes both flaky. Same shape, private static state, and this suite is `.serialized` so its
/// own tests don't race each other either.
final class RMSSDUploadCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestBodies: [Data] = []
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        Self.requestBodies.append(Self.readBody(request))
        let json = "{\"status\":\"ok\",\"days\":1,\"rows_loaded\":1,\"dates\":[]}"
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [RMSSDUploadCapturingURLProtocol.self]
        return URLSession(configuration: c)
    }
    static func reset() { requestBodies = []; requestCount = 0 }

    /// `URLSession` moves `httpBody` into `httpBodyStream` before a custom `URLProtocol` sees the
    /// request — read the stream (same note as `HealthKitUploaderTests`).
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

@Suite(.serialized) struct UploaderRMSSDTests {
    private let ms = HKUnit.secondUnit(with: .milli)
    private let zurich = TimeZone(identifier: "Europe/Zurich")!

    private func hub() -> HubClient {
        HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"), session: RMSSDUploadCapturingURLProtocol.session())
    }

    private func rmssdSample(_ type: HKQuantityType, ms value: Double, at start: Date) -> HKQuantitySample {
        HKQuantitySample(type: type, quantity: HKQuantity(unit: ms, doubleValue: value), start: start, end: start)
    }

    private func decodeMetrics(_ body: Data) throws -> [[String: Any]] {
        let obj = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(obj["data"] as? [String: Any])
        return try #require(data["metrics"] as? [[String: Any]])
    }

    // MARK: - Spec factory

    @Test func factoryUsesTheFrozenWireNameAndMilliseconds() throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType else { return } // pre-27 host: nothing to assert
        let made = HKMetricSpec.hrvRMSSDPerReading(sampleType: type)
        let spec = try #require(made)
        #expect(spec.metricName == HAEMetricName.heartRateVariabilityRMSSD)
        #expect(spec.metricName == "heart_rate_variability_rmssd")
        #expect(spec.units == "ms")
        #expect(spec.sampleType == type)
        #expect(spec.anchorVersion == 2) // B-65: fresh anchor → one 120-day re-send per reading
    }

    @Test func anchorVersionTwoUsesAFreshKey() {
        let type = HKReadKind.stepCount.sampleType!
        let v1 = HKMetricSpec(sampleType: type, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))
        let v2 = HKMetricSpec(sampleType: type, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, anchorVersion: 2, mapSamples: HKSampleMapping.perSample(unit: .count()))
        #expect(v1.anchorVersion == 1)
        #expect(v1.anchorKey == "hk.upload.anchor.\(type.identifier)") // version 1 key unchanged
        #expect(v2.anchorKey == "hk.upload.anchor.\(type.identifier).v2")
    }

    @Test func factoryReturnsNilWhenTheTypeIsUnavailable() {
        #expect(HKMetricSpec.hrvRMSSDPerReading(sampleType: nil) == nil)
    }

    @Test func factoryDefaultsToHKReadKindResolution() {
        // Consumes `HKReadKind.hrvRMSSD` — the factory must agree with the flag on this host.
        #expect((HKMetricSpec.hrvRMSSDPerReading() != nil) == HKReadKind.hrvRMSSDTypeAvailable)
    }

    @Test func appendingNativeRMSSDLeavesTheListUnchangedWhenUnavailable() {
        let steps = HKMetricSpec(sampleType: HKReadKind.stepCount.sampleType!, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))
        let specs = [steps].appendingNativeRMSSD(sampleType: nil)
        #expect(specs.count == 1)
        #expect(specs[0].metricName == HAEMetricName.stepCount)
    }

    @Test func appendingNativeRMSSDAddsExactlyOneSpecWhenAvailable() throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType else { return }
        let steps = HKMetricSpec(sampleType: HKReadKind.stepCount.sampleType!, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))
        let specs = [steps].appendingNativeRMSSD(sampleType: type)
        #expect(specs.map(\.metricName) == [HAEMetricName.stepCount, HAEMetricName.heartRateVariabilityRMSSD])
    }

    // MARK: - Day-average mapping

    @Test func dayAverageEmitsOnePointPerLocalDayWithTheMean() throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType as? HKQuantityType else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zurich
        let d1 = cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 3, minute: 10))!
        let d1b = cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 23, minute: 50))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 0, minute: 5))! // 15 min later, next local day
        let samples: [HKSample] = [
            rmssdSample(type, ms: 40, at: d1), rmssdSample(type, ms: 60, at: d1b), rmssdSample(type, ms: 33, at: d2),
        ]
        let zone = zurich
        let points = HKSampleMapping.dayAverage(unit: ms, timeZone: { zone })(samples)
        let byDate = Dictionary(uniqueKeysWithValues: points.map { ($0.date, $0.qty) })
        #expect(points.count == 2)
        #expect(byDate["2026-09-18 00:00:00 +0200"] == 50)
        #expect(byDate["2026-09-19 00:00:00 +0200"] == 33)
        #expect(points.map(\.date) == points.map(\.date).sorted()) // deterministic order
    }

    @Test func dayAverageIgnoresNonQuantitySamplesAndEmptyPages() throws {
        let zone = zurich
        let mapper = HKSampleMapping.dayAverage(unit: ms, timeZone: { zone })
        #expect(mapper([]).isEmpty)
        let sleepType = try #require(HKReadKind.sleepAnalysis.sampleType as? HKCategoryType)
        let sleep = HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: Date(timeIntervalSince1970: 1_758_000_000), end: Date(timeIntervalSince1970: 1_758_003_600))
        #expect(mapper([sleep]).isEmpty)
    }

    // MARK: - End-to-end through the uploader

    @Test func rmssdIsSentPerReadingWithItsTimestamp() async throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType as? HKQuantityType else { return }
        RMSSDUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let zone = zurich
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let night = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 2, minute: 10))!
        let afternoon = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 14, minute: 0))!
        store.enqueue(HKAnchoredPage(samples: [rmssdSample(type, ms: 42, at: night), rmssdSample(type, ms: 30, at: afternoon)], deletedObjectIDs: [], newAnchor: HKQueryAnchor(fromValue: 7)), for: type)

        let made = HKMetricSpec.hrvRMSSDPerReading(sampleType: type, timeZone: { zone })
        let spec = try #require(made)
        let uploader = HealthKitUploader(store: store, hub: hub(), specs: [spec], defaults: nil)
        let count = try await uploader.sync(spec)

        #expect(count == 2)
        #expect(RMSSDUploadCapturingURLProtocol.requestCount == 1)
        let metrics = try decodeMetrics(RMSSDUploadCapturingURLProtocol.requestBodies[0])
        #expect(metrics.count == 1)
        #expect(metrics[0]["name"] as? String == "heart_rate_variability_rmssd")
        #expect(metrics[0]["units"] as? String == "ms")
        let points = try #require(metrics[0]["data"] as? [[String: Any]])
        #expect(points.count == 2)
        #expect(points.map { $0["date"] as? String } == ["2026-09-20 02:10:00 +0200", "2026-09-20 14:00:00 +0200"])
        #expect(points.map { $0["qty"] as? Double } == [42, 30])
    }

    @Test func unavailableTypeLeavesTheEnvelopeUnchangedAndNothingThrows() async throws {
        RMSSDUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let stepsType = HKReadKind.stepCount.sampleType!
        store.enqueue(HKAnchoredPage(samples: [HKQuantitySample(type: stepsType as! HKQuantityType, quantity: HKQuantity(unit: .count(), doubleValue: 9), start: Date(), end: Date())], deletedObjectIDs: [], newAnchor: nil), for: stepsType)
        let steps = HKMetricSpec(sampleType: stepsType, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))

        // Pre-27 / sim: the RMSSD type resolves to nil → no spec is appended.
        let specs = [steps].appendingNativeRMSSD(sampleType: nil)
        let results = await HealthKitUploader(store: store, hub: hub(), specs: specs, defaults: nil).syncAll()

        #expect(results.count == 1)
        #expect(results[HAEMetricName.heartRateVariabilityRMSSD] == nil)
        #expect(RMSSDUploadCapturingURLProtocol.requestCount == 1)
        let metrics = try decodeMetrics(RMSSDUploadCapturingURLProtocol.requestBodies[0])
        #expect(metrics.map { $0["name"] as? String } == ["step_count"])
    }

    @Test func sdnnMetricIsUntouchedWhenRMSSDIsWiredAlongside() async throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType as? HKQuantityType else { return }
        RMSSDUploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let sdnnType = try #require(HKReadKind.hrvSDNN.sampleType as? HKQuantityType)
        let t = Date(timeIntervalSince1970: 1_758_000_000)
        store.enqueue(HKAnchoredPage(samples: [HKQuantitySample(type: sdnnType, quantity: HKQuantity(unit: ms, doubleValue: 71), start: t, end: t)], deletedObjectIDs: [], newAnchor: nil), for: sdnnType)
        store.enqueue(HKAnchoredPage(samples: [rmssdSample(type, ms: 38, at: t)], deletedObjectIDs: [], newAnchor: nil), for: type)

        let sdnn = HKMetricSpec(sampleType: sdnnType, metricName: HAEMetricName.heartRateVariability, units: "ms", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: ms))
        let specs = [sdnn].appendingNativeRMSSD(sampleType: type)
        let results = await HealthKitUploader(store: store, hub: hub(), specs: specs, defaults: nil).syncAll()

        #expect(results.count == 2)
        #expect(RMSSDUploadCapturingURLProtocol.requestCount == 2)
        let first = try decodeMetrics(RMSSDUploadCapturingURLProtocol.requestBodies[0])
        #expect(first[0]["name"] as? String == "heart_rate_variability") // SDNN, per-sample, unchanged
        let sdnnPoints = try #require(first[0]["data"] as? [[String: Any]])
        #expect(sdnnPoints[0]["qty"] as? Double == 71)
        let second = try decodeMetrics(RMSSDUploadCapturingURLProtocol.requestBodies[1])
        #expect(second[0]["name"] as? String == "heart_rate_variability_rmssd")
    }
}
#endif

#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

/// W-B49B DH-6: the hub is missing Apple Recovery HRV for 09-13…09-18 although Health has it
/// (Toby 2026-09-29: HRV present on 09-14). The RMSSD spec bumps its anchor to v3 and re-reads
/// ONCE from 2026-09-13 local midnight (not the 120-day window) on a phone that already ran v2;
/// afterwards it is anchored again. A fresh install still gets the full 120-day window.
/// Own POST-counting stub (private statics): sharing `RMSSDUploadCapturingURLProtocol` across two
/// parallel suites races its counters.
final class RMSSDRereadCountingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestCount = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
        let json = "{\"status\":\"ok\",\"days\":1,\"rows_loaded\":1,\"dates\":[]}"
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [RMSSDRereadCountingURLProtocol.self]
        return URLSession(configuration: c)
    }
}

@Suite(.serialized) struct RMSSDRereadTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!

    private func hub() -> HubClient {
        HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"), session: RMSSDRereadCountingURLProtocol.session())
    }

    private func sep13(_ zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: 2026, month: 9, day: 13))!
    }

    private func archived(_ value: Int) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: HKQueryAnchor(fromValue: value), requiringSecureCoding: true)
    }

    @Test func factoryBumpsToVersionThreeAndRereadsFromSeptember13() throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType else { return }
        let zone = zurich
        let made = HKMetricSpec.hrvRMSSDPerReading(sampleType: type, timeZone: { zone })
        let spec = try #require(made)
        #expect(spec.anchorVersion == 3)
        #expect(spec.anchorKey == "hk.upload.anchor.\(type.identifier).v3")
        #expect(spec.previousAnchorKey == "hk.upload.anchor.\(type.identifier).v2")
        #expect(spec.rereadSince == sep13(zone))
    }

    @Test func previousKeyOfVersionTwoIsTheUnversionedKey() {
        let type = HKReadKind.stepCount.sampleType!
        let v1 = HKMetricSpec(sampleType: type, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))
        let v2 = HKMetricSpec(sampleType: type, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, anchorVersion: 2, mapSamples: HKSampleMapping.perSample(unit: .count()))
        #expect(v1.previousAnchorKey == nil)
        #expect(v1.rereadSince == nil) // default: no bounded re-read
        #expect(v2.previousAnchorKey == "hk.upload.anchor.\(type.identifier)")
    }

    @Test func versionBumpRereadsOnceFromSeptember13ThenAnchored() async throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType as? HKQuantityType else { return }
        RMSSDRereadCountingURLProtocol.requestCount = 0
        let zone = zurich
        let made = HKMetricSpec.hrvRMSSDPerReading(sampleType: type, timeZone: { zone })
        let spec = try #require(made)
        let defaults = try #require(UserDefaults(suiteName: "rmssd.reread.\(UUID())"))
        defaults.set(try archived(41), forKey: try #require(spec.previousAnchorKey)) // phone ran v2
        let store = FakeHealthStoreReader()
        let t = sep13(zone).addingTimeInterval(86_400 + 3 * 3600) // 09-14 03:00
        store.enqueue(HKAnchoredPage(samples: [HKQuantitySample(type: type, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 44), start: t, end: t)],
                                     deletedObjectIDs: [], newAnchor: HKQueryAnchor(fromValue: 9)), for: type)
        let uploader = HealthKitUploader(store: store, hub: hub(), specs: [spec], defaults: defaults)
        let now = sep13(zone).addingTimeInterval(16 * 86_400)

        #expect(try await uploader.sync(spec, now: now) == 1)
        #expect(try await uploader.sync(spec, now: now) == 0)

        let since = store.sinceSeen[type.identifier] ?? []
        #expect(since.count == 2)
        #expect(since.first == .some(sep13(zone)))   // first pass: from 09-13, not 120 days
        #expect(since.last == .some(nil))            // then anchored
        #expect(defaults.data(forKey: spec.anchorKey) != nil)
        #expect(RMSSDRereadCountingURLProtocol.requestCount == 1)
    }

    @Test func freshInstallStillGetsTheFullWindow() async throws {
        guard let type = HKReadKind.hrvRMSSD.sampleType as? HKQuantityType else { return }
        RMSSDRereadCountingURLProtocol.requestCount = 0
        let zone = zurich
        let made = HKMetricSpec.hrvRMSSDPerReading(sampleType: type, timeZone: { zone })
        let spec = try #require(made)
        let defaults = try #require(UserDefaults(suiteName: "rmssd.fresh.\(UUID())"))
        let store = FakeHealthStoreReader()
        let uploader = HealthKitUploader(store: store, hub: hub(), specs: [spec], defaults: defaults)
        let now = sep13(zone).addingTimeInterval(16 * 86_400)

        _ = try await uploader.sync(spec, now: now)

        let since = store.sinceSeen[type.identifier] ?? []
        #expect(since.first == .some(now.addingTimeInterval(-Double(HealthKitUploader.firstSyncDays) * 86_400)))
    }
}
#endif

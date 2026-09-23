#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

/// Local POST-capturing stub (distinct from `DynamicStubURLProtocol`, which only serves the
/// backload GET shape): records every request body and serves one canned `HAEUploadResponse`.
final class UploadCapturingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestBodies: [Data] = []
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var statusToReturn = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requestCount += 1
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
        c.protocolClasses = [UploadCapturingURLProtocol.self]
        return URLSession(configuration: c)
    }
    static func reset() { requestBodies = []; requestCount = 0; statusToReturn = 200 }

    /// `URLSession` moves a data task's `httpBody` into `httpBodyStream` before handing the
    /// request to a custom `URLProtocol`, so `request.httpBody` reads back `nil` here — read the
    /// stream instead (see the identical note in `HubClientPostTests.swift`).
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

/// Lock-guarded flag a test sets from inside a `@Sendable` completion closure — plain `var`
/// capture-mutation across the closure boundary is a Swift 6 strict-concurrency error.
private final class CompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _completed = false
    var completed: Bool { lock.withLock { _completed } }
    func mark() { lock.withLock { _completed = true } }
}

struct HealthKitUploaderTests {
    private let stepsType = HKQuantityType(.stepCount)

    private func hub() -> HubClient {
        HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"), session: UploadCapturingURLProtocol.session())
    }

    private func makeSample(count: Double, start: Date) -> HKQuantitySample {
        HKQuantitySample(type: stepsType, quantity: HKQuantity(unit: .count(), doubleValue: count), start: start, end: start)
    }

    private func uploader(store: FakeHealthStoreReader, defaults: UserDefaults? = nil) -> HealthKitUploader {
        let spec = HKMetricSpec(
            sampleType: stepsType, metricName: HAEMetricName.stepCount, units: "count",
            backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count())
        )
        return HealthKitUploader(store: store, hub: hub(), specs: [spec], defaults: defaults)
    }

    @Test func uploadsMappedPointsAndAdvancesAnchor() async throws {
        UploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let sample = makeSample(count: 120, start: Date(timeIntervalSince1970: 1_758_000_000))
        let anchor = HKQueryAnchor(fromValue: 1)
        store.enqueue(HKAnchoredPage(samples: [sample], deletedObjectIDs: [], newAnchor: anchor), for: stepsType)

        let count = try await uploader(store: store).sync(HKMetricSpec(sampleType: stepsType, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count())))
        #expect(count == 1)
        #expect(UploadCapturingURLProtocol.requestCount == 1)
        let obj = try #require(try JSONSerialization.jsonObject(with: UploadCapturingURLProtocol.requestBodies[0]) as? [String: Any])
        let data = try #require(obj["data"] as? [String: Any])
        let metrics = try #require(data["metrics"] as? [[String: Any]])
        #expect(metrics[0]["name"] as? String == "step_count")
        let points = try #require(metrics[0]["data"] as? [[String: Any]])
        #expect(points[0]["qty"] as? Double == 120)
    }

    @Test func idempotentRerunUploadsZeroWhenNothingNew() async throws {
        UploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        // No pages enqueued -> anchoredSamples returns an empty page (mirrors "nothing new since anchor").
        let spec = HKMetricSpec(sampleType: stepsType, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))
        let count = try await uploader(store: store).sync(spec)
        #expect(count == 0)
        #expect(UploadCapturingURLProtocol.requestCount == 0) // never POSTs an empty batch
    }

    /// 2026-09-23 connect hang: the first sync of a type (no anchor) must be bounded to
    /// `firstSyncDays`, never the whole store.
    @Test func firstSyncIsBoundedToTheBaselineWindow() async throws {
        let store = FakeHealthStoreReader()
        let spec = HKMetricSpec(sampleType: stepsType, metricName: HAEMetricName.stepCount, units: "count", backgroundFrequency: .hourly, mapSamples: HKSampleMapping.perSample(unit: .count()))
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        _ = try await uploader(store: store).sync(spec, now: now)
        let since = try #require(store.sinceSeen[stepsType.identifier]?.first ?? nil)
        #expect(abs(since.timeIntervalSince(now) + Double(HealthKitUploader.firstSyncDays) * 86_400) < 1)
    }

    @Test func requestAuthorizationThrowsWhenHealthDataUnavailable() async {
        let store = FakeHealthStoreReader()
        store.isHealthDataAvailable = false
        await #expect(throws: HealthKitUploaderError.healthDataUnavailable) {
            try await uploader(store: store).requestAuthorization()
        }
    }

    @Test func startBackgroundDeliveryEnablesAndObservesEachSpec() async throws {
        let store = FakeHealthStoreReader()
        let queries = try await uploader(store: store).startBackgroundDelivery()
        #expect(queries.count == 1)
        #expect(store.backgroundDeliveryEnabled[stepsType.identifier] == .hourly)
        #expect(store.observedTypes == [stepsType.identifier])
    }

    @Test func observerUpdateTriggersUploadAndCallsCompletion() async throws {
        UploadCapturingURLProtocol.reset()
        let store = FakeHealthStoreReader()
        let sample = makeSample(count: 50, start: Date())
        store.enqueue(HKAnchoredPage(samples: [sample], deletedObjectIDs: [], newAnchor: nil), for: stepsType)
        _ = try await uploader(store: store).startBackgroundDelivery()

        let handler = try #require(store.observerHandlers[stepsType.identifier])
        let completedBox = CompletionBox()
        handler({ completedBox.mark() })
        // The handler kicks off a detached Task; give it a beat to run before asserting.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(completedBox.completed)
        #expect(UploadCapturingURLProtocol.requestCount == 1)
    }
}
#endif

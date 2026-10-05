import Foundation
import Synchronization
import Testing
import JICore
@testable import JIHub

/// B-52 p3 (reads: rest): the non-training hub reads the card names — gateSettings, sleepSummary,
/// syncStatus, recoveryInputs — answer from the read-through cache when the hub is really down
/// (connection refused, not a stubbed status), flagged stale; a cold cache stays an honest error.
///
/// Uses its OWN URLProtocol (`B52RestStub`) so this suite never races `HubClientTests`' shared
/// `StubURLProtocol` statics.
@Suite(.serialized) struct B52RestReadsOfflineTests {
    final class B52RestStub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var responses: [String: Data] = [:]
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let body = Self.responses[request.url!.path]
            let resp = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 404 : 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body ?? Data("{\"detail\":\"not found\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static let routes: [String: String] = [
        "/api/v1/planning/gate-settings":
            #"{"preset":"balanced","hr_cap_bpm":175,"avoid_zone5":true,"zone_floors_bpm":[97,117,139,160,176],"hrv_low_nights":2,"updated_at":null}"#,
        "/api/v1/vitals/sleep-summary":
            #"{"score_computed":89,"score_computed_date":"2026-10-04","score_computed_source":"AppleHealth","debt_hours":-1.5,"debt_baseline_hours":7.4,"debt_date":"2026-10-04","debt_source":"AppleHealth","bedtime_consistency_sd_min":null,"bedtime_consistency_nights":0,"bedtime_consistency_sources":[],"last_night_date":"2026-10-04","last_night_duration_sec":30000,"last_night_deep_sleep_sec":2600,"last_night_light_sleep_sec":20000,"last_night_rem_sleep_sec":7400,"last_night_source":"AppleHealth"}"#,
        "/api/v1/ingestion/status": #"{"last_sync":"2026-10-04T05:10:00"}"#,
        "/api/v1/vitals/recovery-inputs": #"{"date":"2026-10-04","days":[]}"#,
    ]

    private func onlineProvider(_ cache: MemoryReadCache) -> HubDataProvider {
        B52RestStub.responses = Self.routes.mapValues { Data($0.utf8) }
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [B52RestStub.self]
        return HubDataProvider(client: HubClient(
            config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"),
            session: URLSession(configuration: c), readCache: cache))
    }

    /// The hub really gone: nothing listens on 127.0.0.1:9 → connection refused → `.network`.
    private func deadProvider(_ cache: MemoryReadCache) -> HubDataProvider {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        return HubDataProvider(client: HubClient(
            config: ConnectionConfig(baseURL: URL(string: "http://127.0.0.1:9")!, token: "t0k"),
            session: URLSession(configuration: c), readCache: cache))
    }

    @Test func warmCacheAnswersEveryRestReadWithTheHubDown() async throws {
        let cache = MemoryReadCache()
        let online = onlineProvider(cache)
        _ = try await online.gateSettings()
        _ = try await online.sleepSummary()
        _ = try await online.syncStatus()
        _ = try await online.recoveryInputsReport(date: "2026-10-04", windowDays: 42)
        #expect(cache.keys.count == 4)

        let dead = deadProvider(cache)
        let (values, staleSince) = try await HubReadTrace.collect {
            (try await dead.gateSettings(), try await dead.sleepSummary(), try await dead.syncStatus(),
             try await dead.recoveryInputsReport(date: "2026-10-04", windowDays: 42))
        }
        #expect(values.0.hrCapBpm == 175)
        #expect(values.1.scoreComputed == 89)
        #expect(values.2.lastSync == "2026-10-04T05:10:00")
        #expect(values.3.date == "2026-10-04")
        #expect(staleSince != nil)
        for path in ["/api/v1/planning/gate-settings", "/api/v1/vitals/sleep-summary", "/api/v1/ingestion/status"] {
            #expect(HubReadStaleness.shared.isStale(path: path))
        }
        #expect(HubReadStaleness.shared.isStale(path: "/api/v1/vitals/recovery-inputs",
                                                query: ["date": "2026-10-04", "window_days": "42"]))
    }

    @Test func coldCacheWithTheHubDownIsAnOfflineErrorNeverAValue() async {
        let dead = deadProvider(MemoryReadCache())
        do {
            _ = try await dead.gateSettings()
            Issue.record("a cold cache must not produce a value")
        } catch {
            #expect(HubClient.isOfflineFailure(error))
        }
        do {
            _ = try await dead.sleepSummary()
            Issue.record("a cold cache must not produce a value")
        } catch {
            #expect(HubClient.isOfflineFailure(error))
        }
    }
}

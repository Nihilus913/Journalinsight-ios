import Foundation
import Testing
import JICore
@testable import JIHub

private func client() -> HubClient {
    HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"), session: StubURLProtocol.session())
}

@Test func sendsBearerAndDecodes() async throws {
    StubURLProtocol.responses["/api/v1/ingestion/status"] = (200, Data("{\"last_sync\":\"2026-09-11T05:10:00\"}".utf8))
    let s: SyncStatus = try await client().get("/api/v1/ingestion/status")
    #expect(s.lastSync == "2026-09-11T05:10:00")
    #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
}

@Test func mapsStatusToNamedErrors() async {
    StubURLProtocol.responses["/api/v1/nutrition/log"] = (409, Data("{\"detail\":\"YAZIO_DUPLICATE\"}".utf8))
    await #expect(throws: HubError.duplicate(detail: "YAZIO_DUPLICATE")) {
        let _: SyncStatus = try await client().get("/api/v1/nutrition/log")
    }
    StubURLProtocol.responses["/api/v1/planning/morning"] = (401, Data("{\"detail\":\"bad token\"}".utf8))
    await #expect(throws: HubError.unauthorized) {
        let _: MorningResponse = try await client().get("/api/v1/planning/morning")
    }
}

@Test func queryItemsAreAppended() async throws {
    StubURLProtocol.responses["/api/v1/vitals/recovery"] = (200, Data("{\"days\":[]}".utf8))
    let _: RecoveryReport = try await client().get("/api/v1/vitals/recovery", query: ["window_days": "28"])
    #expect(StubURLProtocol.lastRequest?.url?.query == "window_days=28")
}

@Test func configRoundTripsThroughSecretStore() throws {
    let store = ConnectionConfigStore(secrets: InMemorySecretStore())
    #expect(try store.load() == nil)
    let cfg = ConnectionConfig(baseURL: URL(string: "http://192.168.1.158:8000")!, token: "abc")
    try store.save(cfg)
    #expect(try store.load() == cfg)
    try store.clear()
    #expect(try store.load() == nil)
}

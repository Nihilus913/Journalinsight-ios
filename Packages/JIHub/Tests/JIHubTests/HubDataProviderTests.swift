import Foundation
import Testing
import JICore
@testable import JIHub

private func fixtureData(_ name: String) throws -> Data {
    // The JIHub tests read the repo-level copies directly (no bundle resource needed).
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // .../Tests/JIHubTests
        .appending(path: "../../../../Fixtures/hub-contract/\(name).json").standardized
    return try Data(contentsOf: url)
}

// Merged into HubClientTests (not a separate @Suite(.serialized) struct): two independent
// .serialized suites still raced on StubURLProtocol's process-global state (confirmed by a failing
// `swift test` run — HubClientTests' own tests broke from cross-suite interleaving), so these two
// tests join HubClientTests' single serialized suite instead, per Task 10's ruling #2.
extension HubClientTests {
    @Test func providerDecodesEveryTodayRoute() async throws {
        StubURLProtocol.responses = [
            "/health": (200, try fixtureData("health")),
            "/api/v1/planning/gate": (200, try fixtureData("planning_gate")),
            "/api/v1/planning/morning": (200, try fixtureData("planning_morning")),
            "/api/v1/planning/morning-verdict": (200, try fixtureData("planning_morning_verdict")),
            "/api/v1/vitals/recovery": (200, try fixtureData("vitals_recovery")),
            "/api/v1/ingestion/status": (200, try fixtureData("ingestion_status")),
        ]
        let p = HubDataProvider(client: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: StubURLProtocol.session()))
        #expect(p.capabilities == .hubAll)
        _ = try await p.health()
        _ = try await p.gate(windowDays: 28)
        _ = try await p.morning()
        _ = try await p.morningVerdict(date: "2026-09-11")
        #expect(try await p.recovery(windowDays: 28).isEmpty == false)
        _ = try await p.syncStatus()
    }

    @Test func connectionTestClassifies() async throws {
        StubURLProtocol.responses = ["/health": (200, Data("{\"status\":\"ok\"}".utf8)), "/api/v1/ingestion/status": (401, Data("{\"detail\":\"x\"}".utf8))]
        let cfg = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "bad")
        #expect(await ConnectionTest.run(cfg, session: StubURLProtocol.session()) == .unauthorized)
    }
}

import Foundation
import Testing
import JICore
@testable import JIHub

/// Exercises `HubDataProvider`'s `KpiTargetsProviding` conformance
/// (`HubDataProvider+KpiTargets.swift`, W3b-L2). Follows `HubDataProviderTrainingTests.swift`'s
/// convention exactly: an extension on `HubClientTests`, built with a `StubURLProtocol`-backed
/// `HubClient` directly (L0 widened `HubDataProvider.client` to internal).
extension HubClientTests {
    private func kpiProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func kpiTargetsDecodesContractFixture() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/kpi-targets"] = (200, Data("""
        {"targets":[{"target_id":6,"metric":"acwr","operator":">","threshold":1.3,"threshold_hi":null,"description":"REDUCE: overreaching risk"}]}
        """.utf8))
        let targets = try await kpiProvider().kpiTargets()
        #expect(targets.count == 1)
        #expect(targets[0].targetId == 6)
        #expect(targets[0].operator == ">")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/kpi-targets")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }
}

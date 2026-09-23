import Foundation
import Testing
import JICore
@testable import JIHub

/// W-B57b — `HubDataProvider+VerdictOverride.swift` against the Wave Card Contract
/// (`POST/DELETE /api/v1/planning/verdict-override`). Same `StubURLProtocol` convention as
/// `HubDataProviderGateRespondTests.swift`.
extension HubClientTests {
    private func verdictOverrideProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func setVerdictOverridePostsAndDecodesTheStoredRow() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/verdict-override"] = (200, Data(#"""
        {"date":"2026-09-23","choice":"full","reason":"Feel good despite metrics","session":"Full Upper","created_at":"2026-09-23T06:01:00+02:00"}
        """#.utf8))

        let o = try await verdictOverrideProvider().setVerdictOverride(date: "2026-09-23", choice: .full, reason: "Feel good despite metrics")

        #expect(o == VerdictOverride(date: "2026-09-23", choice: .full, reason: "Feel good despite metrics",
                                     session: "Full Upper", createdAt: "2026-09-23T06:01:00+02:00"))
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/verdict-override")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func clearVerdictOverrideSendsDeleteWithTheDateQuery() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/verdict-override"] = (204, Data())

        try await verdictOverrideProvider().clearVerdictOverride(date: "2026-09-23")

        #expect(StubURLProtocol.lastRequest?.httpMethod == "DELETE")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/verdict-override")
        #expect(StubURLProtocol.lastRequest?.url?.query == "date=2026-09-23")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func setVerdictOverrideMapsHubRejectionsToNamedErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/verdict-override"] = (401, Data("{\"detail\":\"bad token\"}".utf8))
        await #expect(throws: HubError.unauthorized) {
            _ = try await self.verdictOverrideProvider().setVerdictOverride(date: "2026-09-23", choice: .rest, reason: "")
        }
    }

    @Test func clearVerdictOverrideMapsA422ToHttpWithDetail() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/verdict-override"] = (422, Data("{\"detail\":\"bad date\"}".utf8))
        await #expect(throws: HubError.http(status: 422, detail: "bad date")) {
            try await self.verdictOverrideProvider().clearVerdictOverride(date: "nope")
        }
    }
}

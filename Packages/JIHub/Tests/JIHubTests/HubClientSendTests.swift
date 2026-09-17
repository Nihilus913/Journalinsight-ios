import Foundation
import Testing
import JICore
@testable import JIHub

/// L0 (W3b, B-14) — tests for `HubClient.send` (generic method/body write, e.g. PUT) and
/// `HubClient.delete`. Follows the `HubClientPostTests.swift` convention: an extension on
/// `HubClientTests`, not a new `@Suite(.serialized)` (two independent serialized suites still
/// interleave on `StubURLProtocol`'s process-global static state in practice).
extension HubClientTests {
    private struct SendBody: Encodable, Equatable { var weightKg: Double }
    private struct SendReply: Decodable, Equatable { var exerciseId: Int; var updated: Bool }

    private func sendTestClient() -> HubClient {
        HubClient(config: ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k"), session: StubURLProtocol.session())
    }

    @Test func sendPutSendsBearerAndJSONBodyAndDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/exercises/19"] = (200, Data("{\"exercise_id\":19,\"updated\":true}".utf8))
        let reply: SendReply = try await sendTestClient().send("PUT", "/api/v1/planning/exercises/19", body: SendBody(weightKg: 52.5))
        #expect(reply == SendReply(exerciseId: 19, updated: true))
        #expect(StubURLProtocol.lastRequest?.httpMethod == "PUT")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func sendMapsStatusToNamedErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/exercises/19"] = (401, Data("{\"detail\":\"nope\"}".utf8))
        await #expect(throws: HubError.unauthorized) {
            let _: SendReply = try await self.sendTestClient().send("PUT", "/api/v1/planning/exercises/19", body: SendBody(weightKg: 1))
        }
    }

    @Test func sendWithNilBodyOmitsContentType() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/exercises/19"] = (200, Data("{\"exercise_id\":19,\"updated\":true}".utf8))
        let _: SendReply = try await sendTestClient().send("PUT", "/api/v1/planning/exercises/19", body: SendBody?.none)
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test func deleteSendsBearerAndNoBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/nutrition/log/abc"] = (200, Data("{}".utf8))
        try await sendTestClient().delete("/api/v1/nutrition/log/abc")
        #expect(StubURLProtocol.lastRequest?.httpMethod == "DELETE")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func deleteAppliesQueryItems() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/nutrition/log/abc"] = (200, Data("{}".utf8))
        try await sendTestClient().delete("/api/v1/nutrition/log/abc", query: ["date": "2026-09-17"])
        #expect(StubURLProtocol.lastRequest?.url?.query == "date=2026-09-17")
    }

    @Test func deleteMapsStatusToNamedErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/nutrition/log/abc"] = (409, Data("{\"detail\":\"dup\"}".utf8))
        await #expect(throws: HubError.duplicate(detail: "dup")) {
            try await self.sendTestClient().delete("/api/v1/nutrition/log/abc")
        }
    }
}

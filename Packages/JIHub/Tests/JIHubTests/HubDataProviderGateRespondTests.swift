import Foundation
import Testing
import JICore
@testable import JIHub

/// Exercises `HubDataProvider`'s `GateRespondProviding` conformance
/// (`HubDataProvider+GateRespond.swift`, W5b-L4). Follows
/// `HubDataProviderKpiTargetsTests.swift`'s convention exactly: an extension on `HubClientTests`,
/// built with a `StubURLProtocol`-backed `HubClient` directly.
///
/// Routes verified against the HT routers, not the RN provider:
/// `POST /api/v1/planning/gate/respond` (`app/planning/router.py:325`, `GateRespondOut`) and
/// `POST /api/v1/planning/feel` (`:360`, `FeelOut`).
extension HubClientTests {
    private func gateRespondProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func respondGatePostsToTheRouterPathAndDecodesGateRespondOut() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/gate/respond"] = (200, Data("""
        {"pdf_requested":true,"log_id":41}
        """.utf8))

        let result = try await gateRespondProvider().respondGate(choice: .override, overrideReason: "sore shoulder", windowDays: 7)

        #expect(result.pdfRequested == true)
        #expect(result.logId == 41)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/gate/respond")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    /// `GateRespondOut.log_id` is `number | null` in the RN oracle's own type — a null must stay
    /// nil, never collapse to 0 (CLAUDE.md rule 5).
    @Test func respondGateKeepsANullLogIdNil() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/gate/respond"] = (200, Data("""
        {"pdf_requested":false,"log_id":null}
        """.utf8))

        let result = try await gateRespondProvider().respondGate(choice: .skip, overrideReason: "", windowDays: 7)
        #expect(result.pdfRequested == false)
        #expect(result.logId == nil)
    }

    /// The body is what HT's `GateRespondBody` parses: snake_case `override_reason`/`window_days`
    /// and the literal `"N"` for skip. `URLProtocol` never sees `httpBody` for a streamed request,
    /// so the encoding is asserted directly on the DTO that `respondGate` hands to `client.send`.
    @Test func gateRespondBodyEncodesTheRoutersSnakeCaseContract() throws {
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(GateRespondBody(choice: .skip, overrideReason: "", windowDays: 14))
        ) as? [String: Any]
        #expect(json?["choice"] as? String == "N")
        #expect(json?["override_reason"] as? String == "")
        #expect(json?["window_days"] as? Int == 14)
    }

    @Test func respondGateMapsStatusToNamedErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/gate/respond"] = (502, Data("{\"detail\":\"hub database is down\"}".utf8))
        await #expect(throws: HubError.yazioAuthExpired(detail: "hub database is down")) {
            _ = try await self.gateRespondProvider().respondGate(choice: .yes, overrideReason: "", windowDays: 7)
        }
    }

    @Test func logFeelPostsToTheRouterPathAndDecodesFeelOut() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/feel"] = (200, Data("{\"feel_id\":7}".utf8))

        let result = try await gateRespondProvider().logFeel(feelScore: 4, notes: "legs heavy", date: "2026-09-18")

        #expect(result.feelId == 7)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/feel")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func feelBodyEncodesTheRoutersSnakeCaseContract() throws {
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(FeelBody(feelScore: 3, notes: "ok", date: nil))
        ) as? [String: Any]
        #expect(json?["feel_score"] as? Int == 3)
        #expect(json?["notes"] as? String == "ok")
        #expect(json?["date"] == nil)
    }

    @Test func logFeelMapsStatusToNamedErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/feel"] = (422, Data("{\"detail\":\"feel_score must be 1-5\"}".utf8))
        await #expect(throws: HubError.http(status: 422, detail: "feel_score must be 1-5")) {
            _ = try await self.gateRespondProvider().logFeel(feelScore: 9, notes: "", date: nil)
        }
    }
}

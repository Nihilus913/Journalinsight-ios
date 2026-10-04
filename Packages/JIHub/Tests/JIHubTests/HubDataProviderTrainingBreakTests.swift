import Foundation
import Testing
import JICore
@testable import JIHub

/// W-B91 — `HubDataProvider+TrainingBreak.swift` (`GET/PUT /api/v1/planning/training-break`).
extension HubClientTests {
    private func trainingBreakProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func trainingBreakGetDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/training-break"] = (200, Data(#"{"paused":true,"since":"2026-09-28"}"#.utf8))
        let b = try await trainingBreakProvider().trainingBreak()
        #expect(b == TrainingBreak(paused: true, since: "2026-09-28"))
        #expect(StubURLProtocol.lastRequest?.httpMethod == "GET")
    }

    @Test func setTrainingBreakPutsPausedAndSince() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/training-break"] = (200, Data(#"{"paused":false,"since":null}"#.utf8))
        let b = try await trainingBreakProvider().setTrainingBreak(paused: false, since: nil)
        #expect(b == TrainingBreak(paused: false, since: nil))
        #expect(StubURLProtocol.lastRequest?.httpMethod == "PUT")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/training-break")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }
}

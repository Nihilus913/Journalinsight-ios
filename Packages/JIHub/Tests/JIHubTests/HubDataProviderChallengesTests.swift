import Foundation
import Testing
import JICore
@testable import JIHub

/// Exercises `HubDataProvider`'s `ChallengesProviding` conformance
/// (`HubDataProvider+Challenges.swift`). Same `HubClientTests`-extension convention as
/// `HubDataProviderTrainingTests.swift` (StubURLProtocol's process-global state, run serially).
extension HubClientTests {
    private func challengesProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    /// Same workaround as `HubClientPostTests.readBody` — `URLSession` moves a data task's
    /// `httpBody` into `httpBodyStream` before handing the request to a custom `URLProtocol`.
    private static func readBody(_ request: URLRequest?) -> Data {
        if let body = request?.httpBody { return body }
        guard let stream = request?.httpBodyStream else { return Data() }
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

    private static let sampleChallengeJSON = """
    {"challenge_id":1,"title":"Textbook intervals","hypothesis":"h","start_date":"2026-09-01",
     "target_sessions":4,"session_filter":"interval","status":"active","created_at":null,
     "completed_at":null,"result_note":null,"updated_at":null,
     "progress":{"count":1,"target":4,"execution_score":25,"pace":"on_pace","wants_complete_prompt":false}}
    """

    @Test func challengesDecodesEnvelopeAndContractFixture() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/challenges"] = (200, Data("{\"challenges\":[\(Self.sampleChallengeJSON)]}".utf8))
        let provider = challengesProvider()
        let rows = try await provider.challenges()
        #expect(rows.count == 1)
        #expect(rows[0].challengeId == 1)
        #expect(rows[0].status == .active)
        #expect(rows[0].progress.count == 1)
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/challenges")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func createChallengeSendsPostWithSnakeCaseBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/challenges"] = (200, Data(Self.sampleChallengeJSON.utf8))
        let provider = challengesProvider()
        let result = try await provider.createChallenge(
            ChallengeCreateInput(title: "Textbook intervals", hypothesis: "h", startDate: "2026-09-01", targetSessions: 4)
        )
        #expect(result.challengeId == 1)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        let body = Self.readBody(StubURLProtocol.lastRequest)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["start_date"] as? String == "2026-09-01")
        #expect(decoded?["target_sessions"] as? Int == 4)
    }

    @Test func updateChallengeSendsPatchWithOnlyChangedFields() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/challenges/1"] = (200, Data(Self.sampleChallengeJSON.utf8))
        let provider = challengesProvider()
        _ = try await provider.updateChallenge(challengeId: 1, patch: ChallengeUpdatePatch(resultNote: "done"))
        #expect(StubURLProtocol.lastRequest?.httpMethod == "PATCH")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/challenges/1")
        let body = Self.readBody(StubURLProtocol.lastRequest)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["result_note"] as? String == "done")
        #expect(decoded?["title"] == nil)
        #expect(decoded?["target_sessions"] == nil)
    }

    @Test func updateChallengePropagatesNamedHubErrorOn422() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/challenges/1"] = (422, Data("{\"detail\":\"target_sessions is locked\"}".utf8))
        let provider = challengesProvider()
        await #expect(throws: HubError.http(status: 422, detail: "target_sessions is locked")) {
            _ = try await provider.updateChallenge(challengeId: 1, patch: ChallengeUpdatePatch(targetSessions: 6))
        }
    }

    @Test func archiveChallengeSendsPostToArchivePath() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/challenges/1/archive"] = (200, Data(Self.sampleChallengeJSON.utf8))
        let provider = challengesProvider()
        _ = try await provider.archiveChallenge(challengeId: 1, status: .completed, resultNote: "hit target")
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/challenges/1/archive")
        let body = Self.readBody(StubURLProtocol.lastRequest)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["status"] as? String == "completed")
        #expect(decoded?["result_note"] as? String == "hit target")
    }

    @Test func deleteChallengeSendsDeleteAndPropagatesConflict() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/challenges/1"] = (409, Data("{\"detail\":\"has recorded sessions\"}".utf8))
        let provider = challengesProvider()
        await #expect(throws: HubError.duplicate(detail: "has recorded sessions")) {
            try await provider.deleteChallenge(challengeId: 1)
        }
        #expect(StubURLProtocol.lastRequest?.httpMethod == "DELETE")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/challenges/1")
    }

    @Test func deleteChallengeSucceedsOn204() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/challenges/2"] = (204, Data())
        let provider = challengesProvider()
        try await provider.deleteChallenge(challengeId: 2)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "DELETE")
    }
}

import Foundation
import Testing
import JICore
@testable import JIHub

/// Exercises `HubDataProvider`'s `WeighInProviding` conformance (`HubDataProvider+WeighIn.swift`,
/// W3b-L4). Same `StubURLProtocol`-backed construction as `HubDataProviderTrainingTests`, merged
/// into `HubClientTests`' `.serialized` suite convention.
extension HubClientTests {
    private func weighInProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func logWeighinPostsWithBearerAndDecodesResult() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/vitals/weighin"] = (200, Data("""
        {"status":"ok","weight_kg":82.5,"date":"2026-09-17","garmin_confirmed":true}
        """.utf8))
        let provider = weighInProvider()
        let result = try await provider.logWeighin(weightKg: 82.5, date: "2026-09-17")
        #expect(result.status == "ok")
        #expect(result.weightKg == 82.5)
        #expect(result.garminConfirmed)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/vitals/weighin")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func logWeighinPropagatesGarminUploadErrorDetailOn502() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/vitals/weighin"] = (502, Data("{\"detail\":\"Garmin FIT upload rejected\"}".utf8))
        let provider = weighInProvider()
        await #expect(throws: HubError.yazioAuthExpired(detail: "Garmin FIT upload rejected")) {
            _ = try await provider.logWeighin(weightKg: 82.5, date: nil)
        }
    }
}

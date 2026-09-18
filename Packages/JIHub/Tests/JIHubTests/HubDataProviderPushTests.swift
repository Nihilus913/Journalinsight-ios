import Foundation
import Testing
import JICore
@testable import JIHub

/// Exercises `HubDataProvider`'s `PushTokenProviding` conformance (`HubDataProvider+Push.swift`,
/// W7-L2). Same `StubURLProtocol`-backed construction as `HubDataProviderWeighInTests`, merged into
/// `HubClientTests`' `.serialized` suite convention.
///
/// The body assertion is the L1↔L2 seam: the W7 card fixes the push contract, both lanes code
/// against it, and `contractBody` below is a literal copy — not something derived from the DTO.
extension HubClientTests {
    private static let pushPath = "/api/v1/planning/push-token"

    private func pushProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    /// `URLProtocol` moves a request's `httpBody` into `httpBodyStream`, so the recorded request has
    /// to be drained to see what actually went on the wire.
    private func sentBody(_ request: URLRequest?) throws -> [String: String] {
        let request = try #require(request)
        if let body = request.httpBody {
            return try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    @Test func registerPushTokenPostsTheContractBodyWithBearerAndDecodesTheAck() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.pushPath] = (200, Data("""
        {"ok":true,"registered_at":"2026-09-18T05:10:00+00:00"}
        """.utf8))

        let ack = try await pushProvider().registerPushToken(
            PushTokenRegistration(token: "00ff10", platform: .ios, environment: .sandbox, appVersion: "1.0 (42)")
        )

        #expect(ack.ok)
        #expect(ack.registeredAt == "2026-09-18T05:10:00+00:00")
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.url?.path == Self.pushPath)
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")

        // Byte-level on the body keys — the W7 card's contract, verbatim.
        let contractBody = ["token": "00ff10", "platform": "ios", "environment": "sandbox", "app_version": "1.0 (42)"]
        #expect(try sentBody(StubURLProtocol.lastRequest) == contractBody)
    }

    @Test func registerPushTokenSendsProductionEnvironmentVerbatim() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.pushPath] = (200, Data("{\"ok\":true,\"registered_at\":\"2026-09-18T05:10:00Z\"}".utf8))
        _ = try await pushProvider().registerPushToken(
            PushTokenRegistration(token: "abcd", platform: .ios, environment: .production, appVersion: "2.0 (1)")
        )
        #expect(try sentBody(StubURLProtocol.lastRequest)["environment"] == "production")
    }

    @Test func registerPushTokenSurfacesUnauthorizedWithoutAValidBearer() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.pushPath] = (401, Data("{\"detail\":\"invalid token\"}".utf8))
        await #expect(throws: HubError.unauthorized) {
            _ = try await self.pushProvider().registerPushToken(
                PushTokenRegistration(token: "00ff10", platform: .ios, environment: .sandbox, appVersion: "1.0 (42)")
            )
        }
    }

    @Test func registerPushTokenSurfacesAHubOutageAsANamedError() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.pushPath] = (503, Data("{\"detail\":\"hub asleep\"}".utf8))
        await #expect(throws: HubError.http(status: 503, detail: "hub asleep")) {
            _ = try await self.pushProvider().registerPushToken(
                PushTokenRegistration(token: "00ff10", platform: .ios, environment: .sandbox, appVersion: "1.0 (42)")
            )
        }
    }
}

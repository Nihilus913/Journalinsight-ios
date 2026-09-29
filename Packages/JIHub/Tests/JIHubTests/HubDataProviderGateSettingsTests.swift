import Foundation
import Testing
import JICore
@testable import JIHub

/// B-57 W4 — `GET/PUT /api/v1/planning/gate-settings`. Same StubURLProtocol idiom as
/// `HubDataProviderGoalsTests.swift` (merged into `HubClientTests`' `.serialized` suite).
extension HubClientTests {
    private func gateProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    /// `URLSession` hands the protocol the body as `httpBodyStream`; read it without editing the
    /// shared stub.
    private func gateBody(_ request: URLRequest?) throws -> [String: Any] {
        var data = Data()
        if let stream = request?.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        } else {
            data = try #require(request?.httpBody)
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func getGateSettingsDecodesTheLegacyAnswer() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/gate-settings"] = (200, Data("""
        {"preset":"balanced","hr_cap_bpm":175,"avoid_zone5":true,"zone_floors_bpm":[97,117,139,160,176],"hrv_low_nights":2,"updated_at":null}
        """.utf8))
        let out = try await gateProvider().gateSettings()
        #expect(out.hrCapBpm == 175 && out.avoidZone5 && out.updatedAt == nil)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "GET")
    }
}

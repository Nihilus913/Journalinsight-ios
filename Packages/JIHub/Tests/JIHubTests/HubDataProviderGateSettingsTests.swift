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

    @Test func putGateSettingsSendsSnakeCaseBodyAndDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/gate-settings"] = (200, Data("""
        {"preset":"push","hr_cap_bpm":190,"avoid_zone5":true,"zone_floors_bpm":[97,117,139,160,176],"hrv_low_nights":3,"updated_at":"2026-09-24T07:00:00+00:00"}
        """.utf8))
        let out = try await gateProvider().putGateSettings(
            GateSettingsBody(preset: "push", hrCapBpm: 190, avoidZone5: true, zoneFloorsBpm: [97, 117, 139, 160, 176]))
        #expect(out == GateSettingsDTO(preset: "push", hrCapBpm: 190, avoidZone5: true, zoneFloorsBpm: [97, 117, 139, 160, 176],
                                       hrvLowNights: 3, updatedAt: "2026-09-24T07:00:00+00:00"))
        let req = try #require(StubURLProtocol.lastRequest)
        #expect(req.httpMethod == "PUT")
        #expect(req.url?.path == "/api/v1/planning/gate-settings")
        let body = try gateBody(req)
        #expect(body["hr_cap_bpm"] as? Int == 190)
        #expect(body["preset"] as? String == "push")
        #expect(body["avoid_zone5"] as? Bool == true)
        #expect(body["zone_floors_bpm"] as? [Int] == [97, 117, 139, 160, 176])
        #expect(body["hrCapBpm"] == nil)
    }

    /// No cap = an explicit JSON null (the hub requires the key; omitting it is a 422).
    @Test func noCapIsSentAsAnExplicitNull() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/gate-settings"] = (200, Data("""
        {"preset":"balanced","hr_cap_bpm":null,"avoid_zone5":false,"zone_floors_bpm":null,"hrv_low_nights":2,"updated_at":null}
        """.utf8))
        let out = try await gateProvider().putGateSettings(GateSettingsBody(preset: "balanced", hrCapBpm: nil, avoidZone5: false, zoneFloorsBpm: nil))
        #expect(out.hrCapBpm == nil && out.zoneFloorsBpm == nil)
        let body = try gateBody(StubURLProtocol.lastRequest)
        #expect(body.keys.contains("hr_cap_bpm"))
        #expect(body["hr_cap_bpm"] is NSNull)
        #expect(body["zone_floors_bpm"] is NSNull)
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

    @Test func gateSettings422IsANamedHubError() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/gate-settings"] = (422, Data("{\"detail\":\"bad\"}".utf8))
        await #expect(throws: HubError.self) {
            _ = try await self.gateProvider().putGateSettings(GateSettingsBody(preset: "balanced", hrCapBpm: 175, avoidZone5: false, zoneFloorsBpm: nil))
        }
    }
}

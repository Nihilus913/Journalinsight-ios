import Foundation
import Testing
import JICore
@testable import JIHub

private func onDeviceFixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../Fixtures/hub-contract/\(name).json").standardized
    return try Data(contentsOf: url)
}

/// B-44 Option B — the on-device verdict overlay on `morning()` / `morningVerdict(date:)` and the
/// upload (`POST /api/v1/planning/ondevice-verdict`). Same `StubURLProtocol` convention as
/// `HubDataProviderVerdictOverrideTests.swift`.
/// `URLSession` hands a custom `URLProtocol` the body as a stream (same as `HubClientPostTests`).
private func onDeviceBody(_ request: URLRequest?) -> Data {
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

extension HubClientTests {
    private struct FixedOverlay: MorningVerdictOverlay {
        var mornings: [String: OnDeviceMorning]
        var todayKey: String
        func verdict(day: String) async -> OnDeviceMorning? { mornings[day] }
    }

    private static let mine = OnDeviceMorning(day: "2026-10-05", verdict: "REST — recovery day", reason: "HRV low",
                                              sessionPrescription: nil, gateSignals: [], computedAt: "2026-10-05T05:02:00Z")

    private func provider(overlay: (any MorningVerdictOverlay)?) -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()), verdictOverlay: overlay)
    }

    private func stubMorning() throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/morning"] = (200, try onDeviceFixture("planning_morning"))
        StubURLProtocol.responses["/api/v1/planning/morning-verdict"] = (200, try onDeviceFixture("planning_morning_verdict"))
    }

    @Test func morningCarriesTheOnDeviceVerdictAndKeepsTheHubsOtherFields() async throws {
        try stubMorning()
        let hub = try await provider(overlay: nil).morning()
        let m = try await provider(overlay: FixedOverlay(mornings: ["2026-10-05": Self.mine], todayKey: "2026-10-05")).morning()
        #expect(m.verdict == "REST — recovery day")
        #expect(m.verdictDate == "2026-10-05")
        #expect(m.isStale == false)
        #expect(m.verdictComputedAt == "2026-10-05T05:02:00Z")
        #expect(m.carbWatchFloor == hub.carbWatchFloor)
        #expect(m.verdictOverride == hub.verdictOverride)
        #expect(m.strain == hub.strain)
    }

    @Test func noOnDeviceVerdictFallsBackToTheHubs() async throws {
        try stubMorning()
        let hub = try await provider(overlay: nil).morning()
        let m = try await provider(overlay: FixedOverlay(mornings: [:], todayKey: "2026-10-05")).morning()
        #expect(m == hub)
        let hubV = try await provider(overlay: nil).morningVerdict(date: "2026-10-04")
        let v = try await provider(overlay: FixedOverlay(mornings: [:], todayKey: "2026-10-05")).morningVerdict(date: "2026-10-04")
        #expect(v == hubV)
    }

    @Test func morningVerdictForAnOnDeviceDayIsTheOnDeviceOne() async throws {
        try stubMorning()
        let v = try await provider(overlay: FixedOverlay(mornings: ["2026-10-05": Self.mine], todayKey: "2026-10-05"))
            .morningVerdict(date: "2026-10-05")
        #expect(v.verdict == "REST — recovery day")
        #expect(v.reason == "HRV low")
        #expect(StubURLProtocol.lastRequest == nil)   // no hub call for the day the phone owns
    }

    @Test func hubOnlyDropsTheOverlay() async throws {
        try stubMorning()
        let p = provider(overlay: FixedOverlay(mornings: ["2026-10-05": Self.mine], todayKey: "2026-10-05"))
        let hub = try await provider(overlay: nil).morning()
        #expect(try await p.hubOnly.morning() == hub)
    }

    @Test func uploadPostsSnakeCaseAndDecodesTheStoredRow() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/ondevice-verdict"] = (200, Data(#"""
        {"date":"2026-10-05","verdict":"REST — recovery day","hub_verdict":"GO — Day 2","received_at":"2026-10-05T05:03:00+02:00"}
        """#.utf8))
        let body = OnDeviceVerdictUpload(date: "2026-10-05", verdict: "REST — recovery day", reason: nil, sessionPrescription: nil,
                                         baselineNights: 3, inputsDigest: "ab12", computedAt: "2026-10-05T05:02:00Z")
        let stored = try await provider(overlay: nil).uploadOnDeviceVerdict(body)
        #expect(stored.hubVerdict == "GO — Day 2")
        #expect(StubURLProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/ondevice-verdict")
        let sent = onDeviceBody(StubURLProtocol.lastRequest)
        let json = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(json["baseline_nights"] as? Int == 3)
        #expect(json["inputs_digest"] as? String == "ab12")
        #expect(json["computed_at"] as? String == "2026-10-05T05:02:00Z")
    }
}

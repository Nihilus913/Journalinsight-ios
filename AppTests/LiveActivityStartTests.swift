import Foundation
import Testing
import JICore
@testable import JournalInsight

/// B-21 (push-to-start) exit criteria, XC half: the optional `live_activity_start_token` on the
/// push-token body (with/without), the start-token → re-POST path through `ApnsRegistration`, the
/// observer seam, and the hub's `liveactivity` start payload decoding into `ContentState`.

// MARK: - Contract bodies (literal copies of the B-21 card contract, not derived from the DTO)

private let bodyWithoutStartToken = """
{"app_version":"1.0 (42)","environment":"sandbox","platform":"ios","token":"00ff10"}
"""
private let bodyWithStartToken = """
{"app_version":"1.0 (42)","environment":"sandbox","live_activity_start_token":"0a0bff","platform":"ios","token":"00ff10"}
"""

private func sortedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@Test func registrationWithoutAStartTokenKeepsTheW7BodyByteForByte() throws {
    let registration = ApnsRegistration.registration(deviceToken: Data([0x00, 0xff, 0x10]), environment: .sandbox, appVersion: "1.0 (42)")
    #expect(registration.liveActivityStartToken == nil)
    #expect(try sortedJSON(registration) == bodyWithoutStartToken)
}

@Test func registrationWithAStartTokenAddsTheSnakeCaseKey() throws {
    let hex = ApnsRegistration.hexToken(from: Data([0x0a, 0x0b, 0xff]))
    #expect(hex == "0a0bff") // lowercase, zero nibbles kept — the hub validates ^[0-9a-f]{1,256}$
    let registration = ApnsRegistration.registration(deviceToken: Data([0x00, 0xff, 0x10]), liveActivityStartToken: hex,
                                                     environment: .sandbox, appVersion: "1.0 (42)")
    #expect(try sortedJSON(registration) == bodyWithStartToken)
}

// MARK: - ApnsRegistration start-token path

private final class RecordingPushProvider: PushTokenProviding, @unchecked Sendable { // @unchecked: test-only, MainActor callers
    var registrations: [PushTokenRegistration] = []
    var failNext = false
    func registerPushToken(_ registration: PushTokenRegistration) async throws -> PushTokenAck {
        registrations.append(registration)
        if failNext { failNext = false; throw HubError.unauthorized }
        return PushTokenAck(ok: true, registeredAt: "2026-10-05T03:10:00Z")
    }
}

@MainActor
@Test func aStartTokenAfterTheDeviceTokenRePostsTheRegistrationWithIt() async {
    let provider = RecordingPushProvider()
    let registrar = ApnsRegistration()
    registrar.providerSource = { provider }
    await registrar.receive(deviceToken: Data([0xab, 0xcd]))
    await registrar.receive(liveActivityStartToken: Data([0x01, 0x02]))
    #expect(provider.registrations.count == 2)
    #expect(provider.registrations.first?.liveActivityStartToken == nil)
    #expect(provider.registrations.last?.token == "abcd")
    #expect(provider.registrations.last?.liveActivityStartToken == "0102")
    #expect(registrar.pendingRegistration == nil)
}

@MainActor
@Test func anUnchangedStartTokenIsNotRePosted() async {
    let provider = RecordingPushProvider()
    let registrar = ApnsRegistration()
    registrar.providerSource = { provider }
    await registrar.receive(deviceToken: Data([0xab]))
    await registrar.receive(liveActivityStartToken: Data([0x01]))
    await registrar.receive(liveActivityStartToken: Data([0x01]))
    #expect(provider.registrations.count == 2)
}

@MainActor
@Test func aStartTokenBeforeAnyDeviceTokenIsHeldAndRidesTheFirstRegistration() async {
    let provider = RecordingPushProvider()
    let registrar = ApnsRegistration()
    registrar.providerSource = { provider }
    await registrar.receive(liveActivityStartToken: Data([0xfe]))
    #expect(provider.registrations.isEmpty) // the hub upserts on the device token — nothing to attach to yet
    await registrar.receive(deviceToken: Data([0x10]))
    #expect(provider.registrations.count == 1)
    #expect(provider.registrations.first?.liveActivityStartToken == "fe")
}

@MainActor
@Test func aFailedStartTokenPostStaysPendingAndTheRetryCarriesIt() async {
    let provider = RecordingPushProvider()
    let registrar = ApnsRegistration()
    registrar.providerSource = { provider }
    await registrar.receive(deviceToken: Data([0xab]))
    provider.failNext = true
    await registrar.receive(liveActivityStartToken: Data([0x0c]))
    #expect(registrar.pendingRegistration?.liveActivityStartToken == "0c")
    await registrar.retryPendingRegistration()
    #expect(provider.registrations.last?.liveActivityStartToken == "0c")
    #expect(registrar.pendingRegistration == nil)
}

// MARK: - Observer seam

@MainActor
private final class ObserverLog { var seen: [Data] = []; var streamsMade = 0 }

@MainActor
@Test func theObserverForwardsEveryYieldedTokenAndStartsOnce() async {
    let (stream, continuation) = AsyncStream<Data>.makeStream()
    let log = ObserverLog()
    let done = AsyncStream<Void>.makeStream()
    let observer = LiveActivityStartRegistration()
    observer.start(tokens: { log.streamsMade += 1; return stream }, sink: { data in
        log.seen.append(data)
        if log.seen.count == 2 { done.continuation.finish() }
    })
    observer.start(tokens: { log.streamsMade += 1; return stream }, sink: { _ in })
    #expect(observer.isObserving)
    continuation.yield(Data([0x01]))
    continuation.yield(Data([0x02]))
    for await _ in done.stream {}
    #expect(log.seen == [Data([0x01]), Data([0x02])])
    #expect(log.streamsMade == 1)
    continuation.finish()
}

// MARK: - Hub start payload → ContentState

/// The hub's `liveactivity` start payload (B-21 p1 fixture shape; same file is the `simctl push`
/// payload). ActivityKit decodes `content-state` with a default `JSONDecoder` — numeric `lastUpdate`
/// seconds since 2001-01-01 — so a plain `JSONDecoder()` here is the faithful check.
@Test func theHubStartPayloadDecodesIntoTheVerdictContentState() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("LiveActivityStart/live_activity_start.json")
    let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let aps = try #require(root["aps"] as? [String: Any])
    #expect(aps["event"] as? String == "start")
    #expect(aps["attributes-type"] as? String == String(describing: VerdictActivityAttributes.self))
    let attributes = try JSONSerialization.data(withJSONObject: try #require(aps["attributes"]))
    _ = try JSONDecoder().decode(VerdictActivityAttributes.self, from: attributes)
    let stateData = try JSONSerialization.data(withJSONObject: try #require(aps["content-state"]))
    let state = try JSONDecoder().decode(VerdictActivityAttributes.ContentState.self, from: stateData)
    // The fixture is the hub's own golden (HT tests/fixtures/live_activity_start.json, B-21 p1):
    // readiness / hrCap / nextSession are omitted by the hub and must decode as nil (the app
    // fills them when it adopts the activity); signals carry only key/label/unit/status/value.
    #expect(state.verdictWord == "Modified")
    #expect(state.verdictSession == "Long Z2 45 min")
    #expect(state.verdictTone == "amber")
    #expect(state.readiness == nil)
    #expect(state.hrCap == nil)
    #expect(state.nextSession == nil)
    #expect(state.reason == "HRV 41 ms — under 45")
    #expect(state.signals?.map(\.key) == ["hrv", "sleep_h", "rhr"])
    #expect(state.signals?.map(\.value) == [41, 7.2, 52])
    #expect(state.signals?.map(\.status) == ["amber", "pass", "pass"])
    // 812862600 s after the 2001 reference date = 2026-10-05 03:10 UTC (05:10 CEST, Morning GO).
    #expect(state.lastUpdate == Date(timeIntervalSince1970: 1_791_169_800))
}

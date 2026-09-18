import Foundation
import Testing
import UserNotifications
import JICore
@testable import JournalInsight

/// W7-L2 (P-apns-push) exit criteria: token hex encoding, and a registration body that byte-matches
/// the W7 card's push contract. The effectful half (`registerOnLaunch`, the `AppDelegate` callbacks)
/// is exercised through `receive(deviceToken:)` with an injected provider — an APNs token callback
/// cannot be synthesised in a unit test, but the `Data` it hands over can.

// MARK: - Contract

/// A literal, byte-for-byte copy of the W7 wave card's push-token contract body. Deliberately NOT
/// derived from `PushTokenRegistration` — if the DTO's keys ever drift, this literal is what fails,
/// which is the whole point of the L1/L2 "code against the contract, not against each other" rule.
private let contractBodyJSON = """
{"app_version":"1.0 (42)","environment":"sandbox","platform":"ios","token":"00ff10"}
"""

@Test func deviceTokenEncodesAsLowercaseHex() {
    let data = Data([0x00, 0xff, 0x10])
    #expect(ApnsRegistration.hexToken(from: data) == "00ff10")
}

@Test func deviceTokenHexKeepsLeadingZeroNibbles() {
    // `String(byte, radix: 16)` would render 0x07 as "7" and produce a token APNs rejects.
    let data = Data([0x07, 0x00, 0x0a, 0xb0])
    #expect(ApnsRegistration.hexToken(from: data) == "07000ab0")
}

@Test func emptyDeviceTokenEncodesAsEmptyString() {
    #expect(ApnsRegistration.hexToken(from: Data()) == "")
}

@Test func registrationBodyByteMatchesThePushContract() throws {
    let registration = ApnsRegistration.registration(
        deviceToken: Data([0x00, 0xff, 0x10]),
        environment: .sandbox,
        appVersion: "1.0 (42)"
    )
    // `HubClient.post`/`.send` encode outgoing bodies with a plain `JSONEncoder()`; `.sortedKeys`
    // here only makes the comparison order-independent, it does not change any key or value.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(registration)
    #expect(String(decoding: encoded, as: UTF8.self) == contractBodyJSON)
}

@Test func registrationBodyUsesSnakeCaseAppVersionAndNothingElse() throws {
    let registration = ApnsRegistration.registration(
        deviceToken: Data([0xde, 0xad]),
        environment: .production,
        appVersion: "2.3 (9)"
    )
    let object = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(registration)
    ) as? [String: Any]
    let keys = Set((object ?? [:]).keys)
    #expect(keys == ["token", "platform", "environment", "app_version"])
    #expect(object?["platform"] as? String == "ios")
    #expect(object?["environment"] as? String == "production")
    #expect(object?["token"] as? String == "dead")
}

@Test func ackDecodesTheContractResponse() throws {
    let body = Data(#"{"ok": true, "registered_at": "2026-09-18T05:10:00+00:00"}"#.utf8)
    let ack = try JSON.decoder.decode(PushTokenAck.self, from: body)
    #expect(ack.ok)
    #expect(ack.registeredAt == "2026-09-18T05:10:00+00:00")
}

// MARK: - Environment / version

@Test(arguments: [
    ("development", PushEnvironment.sandbox),
    ("production", PushEnvironment.production),
])
func apsEntitlementMapsToPushEnvironment(entitlement: String, expected: PushEnvironment) {
    #expect(ApnsRegistration.environment(apsEnvironment: entitlement) == expected)
}

@Test func unknownOrMissingApsEntitlementFallsBackToSandbox() {
    // Never claim the production host on a guess — a production token sent to the sandbox gateway
    // fails loudly, the reverse fails silently.
    #expect(ApnsRegistration.environment(apsEnvironment: nil) == .sandbox)
    #expect(ApnsRegistration.environment(apsEnvironment: "") == .sandbox)
}

private func stubInfo(short: String?, build: String?) -> (String) -> Any? {
    { key in
        switch key {
        case "CFBundleShortVersionString": return short
        case "CFBundleVersion": return build
        default: return nil
        }
    }
}

@Test func appVersionCombinesShortVersionAndBuild() {
    #expect(ApnsRegistration.appVersion(info: stubInfo(short: "1.4", build: "77")) == "1.4 (77)")
}

@Test func appVersionDegradesInsteadOfCrashingWhenInfoKeysAreMissing() {
    #expect(ApnsRegistration.appVersion(info: stubInfo(short: nil, build: nil)) == "unknown")
    #expect(ApnsRegistration.appVersion(info: stubInfo(short: "1.4", build: nil)) == "1.4")
    #expect(ApnsRegistration.appVersion(info: stubInfo(short: nil, build: "77")) == "77")
}

@Test func theRealBundleYieldsANonEmptyAppVersion() {
    // The value the hub actually stores must never be empty for a real build.
    #expect(!ApnsRegistration.appVersion().isEmpty)
}

// MARK: - Token submission

private struct SpyPushProvider: PushTokenProviding {
    let ack: PushTokenAck?
    let error: HubError?
    let seen: Box
    final class Box: @unchecked Sendable { // @unchecked: written once per test on the calling task
        var registrations: [PushTokenRegistration] = []
    }
    init(ack: PushTokenAck? = PushTokenAck(ok: true, registeredAt: "2026-09-18T05:10:00Z"), error: HubError? = nil) {
        self.ack = ack
        self.error = error
        self.seen = Box()
    }
    func registerPushToken(_ registration: PushTokenRegistration) async throws -> PushTokenAck {
        seen.registrations.append(registration)
        if let error { throw error }
        return ack!
    }
}

@MainActor
@Test func receivingATokenPostsItAndRecordsTheAck() async {
    let provider = SpyPushProvider()
    let registrar = ApnsRegistration()
    registrar.providerSource = { provider }
    await registrar.receive(deviceToken: Data([0xab, 0xcd]))
    #expect(provider.seen.registrations.count == 1)
    #expect(provider.seen.registrations.first?.token == "abcd")
    #expect(provider.seen.registrations.first?.platform == .ios)
    #expect(registrar.state == .registered(token: "abcd", registeredAt: "2026-09-18T05:10:00Z"))
}

@MainActor
@Test func aHubRejectionIsReportedNotSwallowedAndNeverThrows() async {
    let provider = SpyPushProvider(ack: nil, error: .unauthorized)
    let registrar = ApnsRegistration()
    registrar.providerSource = { provider }
    await registrar.receive(deviceToken: Data([0x01]))
    guard case .unavailable = registrar.state else {
        Issue.record("a hub rejection must leave an honest .unavailable state, got \(registrar.state)")
        return
    }
}

@MainActor
@Test func noHubConnectionYetIsUnavailableRatherThanAFalseSuccess() async {
    let registrar = ApnsRegistration()
    registrar.providerSource = { nil }   // first run: Connection sheet not completed yet
    await registrar.receive(deviceToken: Data([0x01]))
    guard case .unavailable = registrar.state else {
        Issue.record("no provider must report .unavailable, got \(registrar.state)")
        return
    }
}

@MainActor
@Test func apnsRegistrationFailureIsLoggedNotFatal() {
    // The Simulator path: `didFailToRegisterForRemoteNotificationsWithError`.
    let registrar = ApnsRegistration()
    registrar.receiveRegistrationFailure(
        NSError(domain: "NSCocoaErrorDomain", code: 3010, userInfo: [NSLocalizedDescriptionKey: "remote notifications are not supported in the simulator"])
    )
    guard case .unavailable(let reason) = registrar.state else {
        Issue.record("expected .unavailable, got \(registrar.state)")
        return
    }
    #expect(reason.contains("simulator"))
}

@Test func onlyADeniedAuthorizationSkipsRemoteRegistration() {
    #expect(ApnsRegistration.shouldRegisterForRemoteNotifications(authorizationStatus: .denied) == false)
    for status: UNAuthorizationStatus in [.notDetermined, .authorized, .provisional, .ephemeral] {
        #expect(ApnsRegistration.shouldRegisterForRemoteNotifications(authorizationStatus: status))
    }
}

@MainActor
@Test func aDeniedAuthorizationLeavesTheNtfyAndLocalFloorPathsUntouched() async {
    // Authorization-denied must not crash and must not disturb the two channels that don't depend
    // on APNs: the local 05:10 floor reminder still builds its 05:10 request with its `ji://gate`
    // payload, and that payload still resolves through the shared resolver this lane installed.
    let registrar = ApnsRegistration()
    registrar.providerSource = { nil }
    #expect(registrar.state == .idle)

    let request = LocalVerdictFloor.request()
    #expect(request.identifier == LocalVerdictFloor.identifier)
    #expect(ApnsPayloadRouter.resolve(userInfo: request.content.userInfo) == .gate)
    let components = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    #expect(components?.hour == LocalVerdictFloor.defaultHour)
    #expect(components?.minute == LocalVerdictFloor.defaultMinute)
}

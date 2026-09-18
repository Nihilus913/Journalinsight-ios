import Foundation

/// W7-L2 (P-apns-push). The device end of the push-token contract fixed in the W7 wave card:
///
///     POST /api/v1/planning/push-token        (behind HT_API_TOKEN, like every /api/v1/* route)
///     body    {"token": str, "platform": "ios",
///              "environment": "sandbox"|"production", "app_version": str}
///     200     {"ok": true, "registered_at": iso}
///     upsert on `token`
///
/// L1 (the HealthTraining sender) and L2 (this app) code against that contract, not against each
/// other — the keys below are byte-for-byte the card's, and `PushTokenContractTests` /
/// `HubDataProviderPushTests` assert the encoded body against a literal copy of it.

/// `platform` on the wire. One case today; an enum rather than a bare `String` so a typo can't
/// reach the hub, and `RawRepresentable`-`String` `Codable` synthesis keeps it `"ios"` on the wire.
public enum PushPlatform: String, Codable, Sendable, Equatable, CaseIterable {
    case ios
}

/// `environment` on the wire — which APNs host the hub must send this token to. Mirrors the
/// `aps-environment` entitlement the running build was signed with (`development` → `.sandbox`),
/// and pairs with the sender's `HT_APNS_SANDBOX=0|1`.
public enum PushEnvironment: String, Codable, Sendable, Equatable, CaseIterable {
    case sandbox
    case production
}

/// `POST /api/v1/planning/push-token` request body. Explicit snake_case `CodingKeys` for
/// `app_version`: `HubClient.post`/`.send` encode outgoing bodies with a plain `JSONEncoder()`
/// (NOT `JSON.encoder`'s `.convertToSnakeCase` — see `HubClient.swift`), so this type must already
/// be wire-shaped, same convention as `WeighinBody`/`ExerciseUpdate`.
public struct PushTokenRegistration: Codable, Sendable, Equatable {
    /// The APNs device token, lowercase hex (`ApnsRegistration.hexToken(from:)`). The hub upserts
    /// on this column, so a rotated token is a new row and the old one is reaped on a 410.
    public var token: String
    public var platform: PushPlatform
    public var environment: PushEnvironment
    public var appVersion: String

    public init(token: String, platform: PushPlatform = .ios, environment: PushEnvironment, appVersion: String) {
        self.token = token
        self.platform = platform
        self.environment = environment
        self.appVersion = appVersion
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case platform
        case environment
        case appVersion = "app_version"
    }
}

/// `POST /api/v1/planning/push-token` response. Decoded with `JSON.decoder`
/// (`.convertFromSnakeCase`, like every hub response), so `registered_at` lands on `registeredAt`.
/// `registeredAt` stays a `String` — the hub's ISO stamp is carried verbatim, per `JSON`'s rule
/// that timestamps are plain strings in DTOs.
public struct PushTokenAck: Codable, Sendable, Equatable {
    public var ok: Bool
    public var registeredAt: String

    public init(ok: Bool, registeredAt: String) {
        self.ok = ok
        self.registeredAt = registeredAt
    }
}

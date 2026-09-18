import Foundation

/// Previews + tests only, same contract as `MockDataProvider`'s own methods (frozen file — this
/// conformance lives here instead, per the Data seam). There is no mock hub to POST against, so
/// this resolves immediately as a successful upsert, mirroring `MockDataProvider+WeighIn`'s
/// no-op `logWeighin`.
extension MockDataProvider: PushTokenProviding {
    public func registerPushToken(_ registration: PushTokenRegistration) async throws -> PushTokenAck {
        PushTokenAck(ok: true, registeredAt: Self.mockRegisteredAt())
    }

    /// A plain UTC ISO-8601 stamp for the mock's own `registered_at` — never used by the real hub
    /// path, which always echoes the hub's own stamp.
    private static func mockRegisteredAt() -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}

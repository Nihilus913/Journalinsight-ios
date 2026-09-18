public struct SyncStatus: Codable, Sendable, Equatable {
    public var lastSync: String?
    /// W7-L3: additive public initializer — the T2 provider (`JIHealthKit.HealthKitProvider`)
    /// reports its own last anchored-fetch time rather than decoding a hub response.
    public init(lastSync: String? = nil) { self.lastSync = lastSync }
}
public struct HealthResponse: Codable, Sendable, Equatable {
    public var status: String
    /// W7-L3: additive public initializer — see `SyncStatus.init`.
    public init(status: String) { self.status = status }
}

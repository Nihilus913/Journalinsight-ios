import JICore

/// W3a-L1 — `HubDataProvider`'s `EnergyProviding` conformance.
///
/// `HubDataProvider.swift` is frozen this wave (data-seam rule, W3a.md) and declares
/// `private let client: HubClient` — file-scoped `private`, unreachable from this extension file
/// even though both are in `JIHub`. Widening that access level means editing the frozen file,
/// which is out of scope for every screen lane (that's the whole point of the freeze — three
/// lanes would collide on it). Since `HubDataProvider` is a plain `struct` whose only stored
/// property is `client`, `Mirror` recovers it at runtime without touching the frozen file's
/// source or its access control surface: `HubClient.get`/`.post` are `public`, so once the
/// instance is in hand this calls the same code path `recovery(windowDays:)` does.
private extension HubDataProvider {
    var hubClient: HubClient {
        guard let client = Mirror(reflecting: self).children.first(where: { $0.label == "client" })?.value as? HubClient else {
            preconditionFailure("HubDataProvider.client not found via reflection — frozen HubDataProvider.swift's stored-property shape changed; update this Mirror lookup (or, better, widen `client`'s access) in the same commit.")
        }
        return client
    }
}

extension HubDataProvider: EnergyProviding {
    public func energy(windowDays: Int = 7) async throws -> EnergyReport {
        try await hubClient.get("/api/v1/nutrition/energy", query: ["window_days": String(min(windowDays, 365))])
    }

    public func goals() async throws -> Goals {
        try await hubClient.get("/api/v1/planning/goals")
    }
}

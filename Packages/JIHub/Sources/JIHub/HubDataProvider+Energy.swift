import JICore

/// W3a-L1 — `HubDataProvider`'s `EnergyProviding` conformance.
///
/// L0 (W3b, B-14) widened `HubDataProvider.client` to internal, so this extension now uses it
/// directly — the `Mirror`-based `hubClient` workaround this file carried during W3a is gone.
extension HubDataProvider: EnergyProviding {
    public func energy(windowDays: Int = 7) async throws -> EnergyReport {
        try await client.get("/api/v1/nutrition/energy", query: ["window_days": String(min(windowDays, 365))])
    }

    public func goals() async throws -> Goals {
        try await client.get("/api/v1/planning/goals")
    }
}

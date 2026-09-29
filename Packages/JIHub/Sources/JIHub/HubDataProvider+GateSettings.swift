import JICore

/// B-57 W4 — `GateSettingsProviding` over the same `client` seam as the KPI-targets extension.
extension HubDataProvider: GateSettingsProviding {
    public func gateSettings() async throws -> GateSettingsDTO {
        try await client.get("/api/v1/planning/gate-settings")
    }
}

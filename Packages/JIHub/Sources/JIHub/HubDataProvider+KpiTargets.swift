import JICore

/// W3b-L2 — `HubDataProvider`'s `KpiTargetsProviding` conformance. Uses `client` directly (L0/B-14
/// widened it to internal) and `client.send` for the PUT, same seam every other W3 screen lane
/// extension uses.
extension HubDataProvider: KpiTargetsProviding {
    public func kpiTargets() async throws -> [KpiTarget] {
        let response: KpiTargetsResponse = try await client.get("/api/v1/planning/kpi-targets")
        return response.targets
    }

    public func updateKpiTarget(id: Int, threshold: Double, thresholdHi: Double?, description: String?) async throws -> KpiTarget {
        let body = KpiTargetUpdateBody(threshold: threshold, thresholdHi: thresholdHi, description: description)
        return try await client.send("PUT", "/api/v1/planning/kpi-targets/\(id)", body: body)
    }
}

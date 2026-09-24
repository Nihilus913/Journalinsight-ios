import Foundation

/// W3b-L2 — `MockDataProvider`'s `KpiTargetsProviding` conformance. `MockDataProvider.swift`
/// itself is frozen this wave (three screen lanes would collide on it), so this reuses its public
/// `fixtureURL(named:)` lookup, same pattern as `MockDataProvider+Energy.swift`.
extension MockDataProvider: KpiTargetsProviding {
    public func kpiTargets() async throws -> [KpiTarget] {
        try Self.decodeKpiFixture("planning_kpi_targets", as: KpiTargetsResponse.self).targets
    }

    /// No real hub to PUT to — echoes the edit back into the fixture's own row (the mocks'
    /// "echo the posted body" convention) for previews/tests
    /// exercising the happy path (view-model round-trip tests use their own fake
    /// `KpiTargetsProviding` for the 4xx/5xx branches, not this mock).
    public func updateKpiTarget(id: Int, threshold: Double, thresholdHi: Double?, description: String?) async throws -> KpiTarget {
        var targets = try await kpiTargets()
        guard let idx = targets.firstIndex(where: { $0.targetId == id }) else {
            throw HubError.decoding("kpi target \(id) not found in fixture")
        }
        targets[idx].threshold = threshold
        targets[idx].thresholdHi = thresholdHi
        targets[idx].description = description
        return targets[idx]
    }

    private static func decodeKpiFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Self.fixtureURL(named: name) else { throw HubError.decoding("missing fixture \(name)") }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }
}

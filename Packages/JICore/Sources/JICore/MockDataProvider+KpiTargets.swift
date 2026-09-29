import Foundation

/// W3b-L2 — `MockDataProvider`'s `KpiTargetsProviding` conformance. `MockDataProvider.swift`
/// itself is frozen this wave (three screen lanes would collide on it), so this reuses its public
/// `fixtureURL(named:)` lookup, same pattern as `MockDataProvider+Energy.swift`.
extension MockDataProvider: KpiTargetsProviding {
    public func kpiTargets() async throws -> [KpiTarget] {
        try Self.decodeKpiFixture("planning_kpi_targets", as: KpiTargetsResponse.self).targets
    }

    private static func decodeKpiFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Self.fixtureURL(named: name) else { throw HubError.decoding("missing fixture \(name)") }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }
}

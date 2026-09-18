import Foundation

/// W5b-L1 — `MockDataProvider`'s `DataQualityProviding` conformance. `MockDataProvider.swift`
/// itself is frozen this wave (five lanes would collide on it), so this reuses its public
/// `fixtureURL(named:)` lookup, same pattern as `MockDataProvider+KpiTargets.swift`.
///
/// Serves the three hub-contract fixtures of record and runs them through the SAME
/// `DataQualityReport.merge` the hub provider uses, so the ported contract test really does
/// exercise one merge across both providers rather than two look-alikes.
extension MockDataProvider: DataQualityProviding {
    public func dataQuality() async throws -> DataQualityReport {
        DataQualityReport.merge(
            qualityScore: try Self.decodeDataQualityFixture("ingestion_quality_score", as: QualityScoreResponse.self),
            freshness: try Self.decodeDataQualityFixture("ingestion_freshness", as: FreshnessResponse.self),
            sourceTrust: try Self.decodeDataQualityFixture("vitals_source_trust", as: SourceTrustResponse.self)
        )
    }

    private static func decodeDataQualityFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Self.fixtureURL(named: name) else { throw HubError.decoding("missing fixture \(name)") }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }
}

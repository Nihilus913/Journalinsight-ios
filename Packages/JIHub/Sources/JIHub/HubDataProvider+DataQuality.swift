import Foundation
import JICore

/// W5b-L1 (P-data-quality). `HubDataProvider.client` is internal (L0, W3b, B-14) — this
/// conformance uses it directly, same convention as the other `HubDataProvider+*.swift` slices.
///
/// Endpoints, grepped from the HT routers (never the RN provider):
/// `GET /api/v1/ingestion/quality-score` (`app/ingestion/router.py:306`, `QualityScoreResponse`),
/// `GET /api/v1/ingestion/freshness` (`app/ingestion/router.py:270`, `FreshnessResponse`),
/// `GET /api/v1/vitals/source-trust` (`app/vitals/router.py:152`, `SourceTrustResponse`).
extension HubDataProvider: DataQualityProviding {
    /// Fans the one screen call out to the three GETs concurrently (oracle: `Promise.all` in
    /// `HubDataProvider.getDataQuality`) and merges with the shared `DataQualityReport.merge`.
    ///
    /// `try await (…)` on the three `async let`s propagates the FIRST failing leg's `HubError`
    /// untouched — a named case stays named (rule 4), and a half-answered report is never
    /// fabricated (rule 5).
    public func dataQuality() async throws -> DataQualityReport {
        async let quality: QualityScoreResponse = client.get("/api/v1/ingestion/quality-score")
        async let freshness: FreshnessResponse = client.get("/api/v1/ingestion/freshness")
        async let trust: SourceTrustResponse = client.get("/api/v1/vitals/source-trust")
        let (q, f, t) = try await (quality, freshness, trust)
        return DataQualityReport.merge(qualityScore: q, freshness: f, sourceTrust: t)
    }
}

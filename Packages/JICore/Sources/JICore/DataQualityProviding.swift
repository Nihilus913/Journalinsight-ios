import Foundation

/// W5b-L1 (P-data-quality) — the Data Quality screen's own hub slice, added fresh rather than
/// growing the frozen `HealthDataProvider` (same rationale as `KpiTargetsProviding`):
/// each screen lane owns its own protocol so parallel lanes never collide
/// on one shared interface.
///
/// Deliberately ONE method over three hub GETs, exactly as the oracle has it
/// (`DataProvider.getDataQuality`, `mobile/src/data/DataProvider.ts:136`): the screen has one
/// loading state and one error state, so the fan-out and the merge belong behind the seam, not in
/// the view model.
public protocol DataQualityProviding: Sendable {
    /// `GET /api/v1/ingestion/quality-score` + `GET /api/v1/ingestion/freshness` +
    /// `GET /api/v1/vitals/source-trust`, merged into one `DataQualityReport`
    /// (`DataQualityReport.merge`). Throws the first failing leg's `HubError` — a partial report
    /// is never fabricated (rule 5).
    func dataQuality() async throws -> DataQualityReport
}

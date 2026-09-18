import Foundation

/// W5b-L1 (P-data-quality). The Data Quality detail screen's wire types — the three independent
/// hub reports (`GET /api/v1/ingestion/quality-score`, `GET /api/v1/ingestion/freshness`,
/// `GET /api/v1/vitals/source-trust`) plus the merged, screen-shaped `DataQualityReport` both
/// providers resolve.
///
/// Oracle: `mobile/src/data/types.ts:490–556` (`QualityScoreEntry`/`FreshnessEntry`/
/// `SourceTrustEntry`/`DataQualityReport`) and `HubDataProvider.getDataQuality` (`:413–426`),
/// whose three `…Raw` envelope interfaces are mirrored here as `QualityScoreResponse`/
/// `FreshnessResponse`/`SourceTrustResponse`. Decode-only (the hub owns every one of these
/// shapes), so plain auto-generated `CodingKeys` are fine — `JSON.decoder`'s
/// `.convertFromSnakeCase` handles the wire's snake_case.
///
/// Every field the hub declares `| null` is Optional here: a missing sub-score reads as "not
/// scored", never as 0 (CLAUDE.md rule 5).

/// Per-component 0–1 sub-scores behind a row's `composite` (`app/ingestion/quality_score.py`).
/// All three are nullable: a (source, metric) row is scored only on the components that apply to
/// it. Provenance (E14-3) has no sub-score anywhere — see `DataQualityReport.provenanceGap`.
public struct QualitySubScores: Codable, Sendable, Equatable {
    public var freshness: Double?
    public var rangeValidity: Double?
    public var trust: Double?
    public init(freshness: Double?, rangeValidity: Double?, trust: Double?) {
        self.freshness = freshness; self.rangeValidity = rangeValidity; self.trust = trust
    }
}

/// One `(source, metric)` row of `GET /api/v1/ingestion/quality-score`.
public struct QualityScoreEntry: Codable, Sendable, Equatable, Identifiable {
    public var source: String
    public var dsoKey: Int
    public var metric: String
    public var metricLabel: String
    /// 0–1 weighted mean over whichever sub-scores apply to this row, renormalized so their
    /// weights sum to 1 (`app/ingestion/quality_score.py`).
    public var composite: Double
    public var subScores: QualitySubScores
    /// Per-row renormalized weights actually used for `composite` — only the keys present in
    /// `componentsAvailable`.
    public var weightsUsed: [String: Double]
    public var componentsAvailable: [String]
    /// Always includes `"provenance"`.
    public var componentsMissing: [String]

    /// The join key `data-quality.tsx` pairs a quality row with its freshness detail on.
    public var id: String { DataQualityReport.joinKey(source: source, metric: metric) }

    public init(
        source: String, dsoKey: Int, metric: String, metricLabel: String, composite: Double,
        subScores: QualitySubScores, weightsUsed: [String: Double],
        componentsAvailable: [String], componentsMissing: [String]
    ) {
        self.source = source; self.dsoKey = dsoKey; self.metric = metric
        self.metricLabel = metricLabel; self.composite = composite; self.subScores = subScores
        self.weightsUsed = weightsUsed; self.componentsAvailable = componentsAvailable
        self.componentsMissing = componentsMissing
    }
}

/// One detected coverage gap inside a metric's history.
public struct FreshnessGap: Codable, Sendable, Equatable {
    public var start: String
    public var end: String
    public var days: Int
    public init(start: String, end: String, days: Int) {
        self.start = start; self.end = end; self.days = days
    }
}

/// The hub's freshness traffic light (`app/ingestion/freshness.py`). Decoded as an enum so an
/// unexpected value fails loudly at the seam instead of silently rendering as a fourth colour.
public enum FreshnessState: String, Codable, Sendable, Equatable {
    case green, amber, red
}

/// One `(source, metric)` row of `GET /api/v1/ingestion/freshness`.
public struct FreshnessEntry: Codable, Sendable, Equatable, Identifiable {
    public var source: String
    public var dsoKey: Int
    public var metric: String
    public var metricLabel: String
    public var state: FreshnessState
    public var lastDate: String?
    public var firstDate: String?
    public var daysStale: Int?
    public var cadenceDays: Int?
    /// False for sparse-by-design metrics (activity, vo2max) — `gaps`/`gapCount`/
    /// `totalMissingDays` are nil there; `state`/`daysStale` still apply (`get_freshness`'s own
    /// doc comment in `app/ingestion/router.py`).
    public var coverageChecked: Bool
    public var gaps: [FreshnessGap]?
    public var gapCount: Int?
    public var totalMissingDays: Int?

    public var id: String { DataQualityReport.joinKey(source: source, metric: metric) }

    public init(
        source: String, dsoKey: Int, metric: String, metricLabel: String, state: FreshnessState,
        lastDate: String?, firstDate: String?, daysStale: Int?, cadenceDays: Int?,
        coverageChecked: Bool, gaps: [FreshnessGap]?, gapCount: Int?, totalMissingDays: Int?
    ) {
        self.source = source; self.dsoKey = dsoKey; self.metric = metric
        self.metricLabel = metricLabel; self.state = state; self.lastDate = lastDate
        self.firstDate = firstDate; self.daysStale = daysStale; self.cadenceDays = cadenceDays
        self.coverageChecked = coverageChecked; self.gaps = gaps; self.gapCount = gapCount
        self.totalMissingDays = totalMissingDays
    }
}

/// One `(source, metric class)` row of `GET /api/v1/vitals/source-trust`. `trustTier` stays a
/// `String` (not an enum) exactly as the oracle has it — `ref.source_trust` is seeded data the
/// hub may extend with a new tier without an app release, and the screen falls back to printing
/// the raw tier when it doesn't recognise one.
public struct SourceTrustEntry: Codable, Sendable, Equatable, Identifiable {
    public var dsoKey: Int
    public var sourceLabel: String
    public var metricClass: String
    public var trustTier: String
    public var note: String

    public var id: String { "\(dsoKey)::\(metricClass)" }

    public init(dsoKey: Int, sourceLabel: String, metricClass: String, trustTier: String, note: String) {
        self.dsoKey = dsoKey; self.sourceLabel = sourceLabel; self.metricClass = metricClass
        self.trustTier = trustTier; self.note = note
    }
}

/// `GET /api/v1/ingestion/quality-score` envelope (`QualityScoreResponse`, `app/ingestion/
/// router.py:306`). The response's top-level `weights` map is deliberately not decoded — the
/// screen reads the per-row renormalized `weightsUsed` instead, same as the oracle.
public struct QualityScoreResponse: Codable, Sendable, Equatable {
    public var generatedAt: String
    public var provenanceGap: String
    public var qualityScore: [QualityScoreEntry]
    public init(generatedAt: String, provenanceGap: String, qualityScore: [QualityScoreEntry]) {
        self.generatedAt = generatedAt; self.provenanceGap = provenanceGap
        self.qualityScore = qualityScore
    }
}

/// `GET /api/v1/ingestion/freshness` envelope (`FreshnessResponse`, `app/ingestion/router.py:270`).
public struct FreshnessResponse: Codable, Sendable, Equatable {
    public var generatedAt: String
    public var freshness: [FreshnessEntry]
    public init(generatedAt: String, freshness: [FreshnessEntry]) {
        self.generatedAt = generatedAt; self.freshness = freshness
    }
}

/// `GET /api/v1/vitals/source-trust` envelope (`SourceTrustResponse`, `app/vitals/router.py:152`)
/// — `{"sources": [...]}`.
public struct SourceTrustResponse: Codable, Sendable, Equatable {
    public var sources: [SourceTrustEntry]
    public init(sources: [SourceTrustEntry]) { self.sources = sources }
}

/// The combined, screen-shaped envelope one `DataQualityProviding.dataQuality()` call resolves —
/// one screen, one loading/error state, over three independent hub GETs rather than the view
/// juggling three (oracle: `DataQualityReport`'s own comment in `types.ts`).
public struct DataQualityReport: Codable, Sendable, Equatable {
    public var generatedAt: String
    public var qualityScore: [QualityScoreEntry]
    public var freshness: [FreshnessEntry]
    public var sourceTrust: [SourceTrustEntry]
    /// The quality-score response's standing note that provenance (E14-3) carries no sub-score
    /// yet; surfaced once on the screen, not per row.
    public var provenanceGap: String

    public init(
        generatedAt: String, qualityScore: [QualityScoreEntry], freshness: [FreshnessEntry],
        sourceTrust: [SourceTrustEntry], provenanceGap: String
    ) {
        self.generatedAt = generatedAt; self.qualityScore = qualityScore
        self.freshness = freshness; self.sourceTrust = sourceTrust
        self.provenanceGap = provenanceGap
    }

    /// The ONE merge, shared by `HubDataProvider` and `MockDataProvider` so the ported contract
    /// test (`mobile/__tests__/dataQuality.contract.test.ts`) really does describe both. Field for
    /// field the oracle's `HubDataProvider.getDataQuality` return literal: `generated_at` and
    /// `provenance_gap` come from the quality-score response (the freshness response's own
    /// `generated_at` is dropped, as in RN), the three row arrays are passed through untouched.
    public static func merge(
        qualityScore: QualityScoreResponse,
        freshness: FreshnessResponse,
        sourceTrust: SourceTrustResponse
    ) -> DataQualityReport {
        DataQualityReport(
            generatedAt: qualityScore.generatedAt,
            qualityScore: qualityScore.qualityScore,
            freshness: freshness.freshness,
            sourceTrust: sourceTrust.sources,
            provenanceGap: qualityScore.provenanceGap
        )
    }

    /// `(source, metric)` — the key the screen pairs a quality row with its freshness detail on
    /// (oracle `joinKey` in `app/data-quality.tsx`). Defined once here so the view, the view
    /// model and the contract test can never drift on the separator.
    public static func joinKey(source: String, metric: String) -> String { "\(source)::\(metric)" }
}

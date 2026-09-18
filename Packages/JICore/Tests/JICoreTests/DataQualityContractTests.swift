import Foundation
import Testing
@testable import JICore

/// W5b-L1 — port of the oracle's `mobile/__tests__/dataQuality.contract.test.ts`.
///
/// RN ran the same suite over `describe.each([MockDataProvider, HubDataProvider])`. Swift splits
/// it across packages (JIHub can't be imported from JICore's tests): this file is the
/// `MockDataProvider` half, and `JIHubTests/HubDataProviderDataQualityTests.swift` runs the same
/// assertion set over a `StubURLProtocol`-backed `HubDataProvider` serving the very same three
/// fixtures. `assertDataQualityContract` below is the shared body — kept here, `public` on a
/// `@testable`-visible helper would not reach the other package, so the hub-side file restates the
/// four checks against the same rules (see its own comment).
@Suite struct DataQualityContractTests {

    private func report() async throws -> DataQualityReport {
        try await MockDataProvider().dataQuality()
    }

    /// RN: "resolves the combined quality_score/freshness/source_trust envelope".
    @Test func resolvesCombinedEnvelope() async throws {
        let r = try await report()
        #expect(!r.generatedAt.isEmpty)
        #expect(!r.provenanceGap.isEmpty)
        #expect(r.qualityScore.count > 0)
        #expect(r.freshness.count > 0)
        #expect(r.sourceTrust.count > 0)
    }

    /// RN: "every quality_score row has a real composite + sub_scores shape".
    @Test func everyQualityRowHasCompositeAndSubScores() async throws {
        for row in try await report().qualityScore {
            #expect(!row.source.isEmpty)
            #expect(!row.metric.isEmpty)
            #expect(!row.metricLabel.isEmpty)
            #expect(row.composite >= 0)
            #expect(row.composite <= 1)
            // E14-3 — provenance carries no sub-score anywhere; every row must say so
            // explicitly rather than silently omitting it.
            #expect(row.componentsMissing.contains("provenance"))
            // A component the hub says is available must carry a real weight for this row.
            for component in row.componentsAvailable {
                #expect(row.weightsUsed[component] != nil, "\(row.id) claims \(component) without a weight")
            }
        }
    }

    /// RN: "every freshness row has a real traffic-light state + coverage shape". The state enum
    /// itself replaces RN's `["green","amber","red"]` membership check — an unknown value fails to
    /// decode at the seam instead.
    @Test func everyFreshnessRowHasTrafficLightAndCoverageShape() async throws {
        for row in try await report().freshness {
            if row.coverageChecked {
                #expect(row.gaps != nil)
                #expect(row.gapCount != nil)
                #expect(row.totalMissingDays != nil)
            } else {
                // Sparse-by-design metrics (activity, vo2max) carry no gap detail.
                #expect(row.gaps == nil)
                #expect(row.gapCount == nil)
                #expect(row.totalMissingDays == nil)
            }
        }
    }

    /// RN: "every source_trust row has a real tier + reason note".
    @Test func everySourceTrustRowHasTierAndNote() async throws {
        for row in try await report().sourceTrust {
            #expect(!row.sourceLabel.isEmpty)
            #expect(!row.metricClass.isEmpty)
            #expect(!row.trustTier.isEmpty)
            #expect(!row.note.isEmpty)
        }
    }

    /// RN: "quality_score and freshness rows share the same (source, metric) keys" — the join the
    /// screen's freshness detail depends on. A hub-side change that breaks it must fail a test
    /// instead of silently rendering "—" app-wide.
    @Test func qualityAndFreshnessShareJoinKeys() async throws {
        let r = try await report()
        let qKeys = Set(r.qualityScore.map { DataQualityReport.joinKey(source: $0.source, metric: $0.metric) })
        let fKeys = Set(r.freshness.map { DataQualityReport.joinKey(source: $0.source, metric: $0.metric) })
        #expect(qKeys == fKeys)
    }

    /// The merge itself (oracle `HubDataProvider.getDataQuality`'s return literal): `generatedAt`
    /// and `provenanceGap` come from the quality-score leg, never from freshness.
    @Test func mergeTakesGeneratedAtAndProvenanceFromQualityScore() {
        let qs = QualityScoreResponse(generatedAt: "2026-09-12T14:47:58Z", provenanceGap: "note", qualityScore: [])
        let fr = FreshnessResponse(generatedAt: "1999-01-01T00:00:00Z", freshness: [])
        let st = SourceTrustResponse(sources: [])
        let merged = DataQualityReport.merge(qualityScore: qs, freshness: fr, sourceTrust: st)
        #expect(merged.generatedAt == "2026-09-12T14:47:58Z")
        #expect(merged.provenanceGap == "note")
    }

    /// Nullable sub-scores stay Optional end to end — a row scored on freshness alone must read
    /// as "not scored" for the other two, never as 0 (rule 5).
    @Test func missingSubScoresDecodeAsNilNotZero() async throws {
        let rows = try await report().qualityScore
        let freshnessOnly = rows.first { $0.componentsAvailable == ["freshness"] }
        let row = try #require(freshnessOnly, "fixture should contain a freshness-only row")
        #expect(row.subScores.rangeValidity == nil)
        #expect(row.subScores.trust == nil)
        #expect(row.subScores.freshness != nil)
    }
}

import Foundation
import Testing
import JICore
@testable import JIHub

/// W5b-L1 — exercises `HubDataProvider`'s `DataQualityProviding` conformance
/// (`HubDataProvider+DataQuality.swift`). Follows `HubDataProviderKpiTargetsTests.swift`'s
/// convention exactly: an extension on `HubClientTests`, built with a `StubURLProtocol`-backed
/// `HubClient` directly (L0 widened `HubDataProvider.client` to internal).
///
/// The hub half of the ported `mobile/__tests__/dataQuality.contract.test.ts`: RN's `fixtureFetch`
/// served the three recorded fixtures per URL fragment, and this does the same by serving the
/// bytes of the hub-contract fixtures of record (reached through `MockDataProvider.fixtureURL`,
/// JICore's `Bundle.module`) from `StubURLProtocol`. The Mock half of the same suite lives in
/// `JICoreTests/DataQualityContractTests.swift`; both go through one
/// `DataQualityReport.merge`.
extension HubClientTests {
    private static let qualityPath = "/api/v1/ingestion/quality-score"
    private static let freshnessPath = "/api/v1/ingestion/freshness"
    private static let trustPath = "/api/v1/vitals/source-trust"

    private func dataQualityProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = try #require(MockDataProvider.fixtureURL(named: name), "missing hub-contract fixture \(name)")
        return try Data(contentsOf: url)
    }

    /// Serves all three legs from the fixtures of record.
    private func stubAllThree() throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.qualityPath] = (200, try fixtureData("ingestion_quality_score"))
        StubURLProtocol.responses[Self.freshnessPath] = (200, try fixtureData("ingestion_freshness"))
        StubURLProtocol.responses[Self.trustPath] = (200, try fixtureData("vitals_source_trust"))
    }

    // MARK: - Contract (ported from dataQuality.contract.test.ts)

    @Test func dataQualityResolvesCombinedEnvelopeFromThreeGets() async throws {
        try stubAllThree()
        let report = try await dataQualityProvider().dataQuality()

        #expect(!report.generatedAt.isEmpty)
        #expect(!report.provenanceGap.isEmpty)
        #expect(report.qualityScore.count > 0)
        #expect(report.freshness.count > 0)
        #expect(report.sourceTrust.count > 0)
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func dataQualityRowsKeepTheContractShape() async throws {
        try stubAllThree()
        let report = try await dataQualityProvider().dataQuality()

        for row in report.qualityScore {
            #expect(row.composite >= 0 && row.composite <= 1)
            #expect(row.componentsMissing.contains("provenance"))
        }
        for row in report.freshness {
            if row.coverageChecked {
                #expect(row.gaps != nil && row.gapCount != nil && row.totalMissingDays != nil)
            } else {
                #expect(row.gaps == nil && row.gapCount == nil && row.totalMissingDays == nil)
            }
        }
        for row in report.sourceTrust {
            #expect(!row.trustTier.isEmpty)
            #expect(!row.note.isEmpty)
        }
    }

    @Test func dataQualityJoinsQualityAndFreshnessOnSourceAndMetric() async throws {
        try stubAllThree()
        let report = try await dataQualityProvider().dataQuality()
        let qKeys = Set(report.qualityScore.map { DataQualityReport.joinKey(source: $0.source, metric: $0.metric) })
        let fKeys = Set(report.freshness.map { DataQualityReport.joinKey(source: $0.source, metric: $0.metric) })
        #expect(qKeys == fKeys)
    }

    // MARK: - Each GET independently, and the failure paths

    @Test func qualityScoreGetDecodesItsOwnEnvelope() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.qualityPath] = (200, Data("""
        {"generated_at":"2026-09-12T14:47:58Z","weights":{"freshness":0.4},"provenance_gap":"no sub-score yet",
         "quality_score":[{"source":"GarminAPI","dso_key":2,"metric":"sleep","metric_label":"Sleep","composite":0.82,
         "sub_scores":{"freshness":1.0,"range_validity":null,"trust":0.6},"weights_used":{"freshness":0.6,"trust":0.4},
         "components_available":["freshness","trust"],"components_missing":["range_validity","provenance"]}]}
        """.utf8))
        let response: QualityScoreResponse = try await dataQualityProvider().client.get(Self.qualityPath)
        #expect(response.qualityScore.count == 1)
        #expect(response.qualityScore[0].dsoKey == 2)
        #expect(response.qualityScore[0].weightsUsed["trust"] == 0.4)
        // Nullable sub-score stays nil, never 0 (rule 5).
        #expect(response.qualityScore[0].subScores.rangeValidity == nil)
        #expect(StubURLProtocol.lastRequest?.url?.path == Self.qualityPath)
    }

    @Test func freshnessGetDecodesSparseAndCoveredRows() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.freshnessPath] = (200, Data("""
        {"generated_at":"2026-09-12T14:47:58Z","freshness":[
         {"source":"GarminAPI","dso_key":2,"metric":"sleep","metric_label":"Sleep","state":"green",
          "last_date":"2026-09-12","first_date":"2024-01-01","days_stale":0,"cadence_days":1,
          "coverage_checked":true,"gaps":[{"start":"2024-07-20","end":"2024-07-21","days":2}],
          "gap_count":1,"total_missing_days":2},
         {"source":"GarminAPI","dso_key":2,"metric":"vo2max","metric_label":"VO2max","state":"amber",
          "last_date":null,"first_date":null,"days_stale":null,"cadence_days":null,
          "coverage_checked":false,"gaps":null,"gap_count":null,"total_missing_days":null}]}
        """.utf8))
        let response: FreshnessResponse = try await dataQualityProvider().client.get(Self.freshnessPath)
        #expect(response.freshness.count == 2)
        #expect(response.freshness[0].state == .green)
        #expect(response.freshness[0].gaps?.first?.days == 2)
        #expect(response.freshness[1].coverageChecked == false)
        #expect(response.freshness[1].gaps == nil)
        #expect(response.freshness[1].daysStale == nil)
        #expect(StubURLProtocol.lastRequest?.url?.path == Self.freshnessPath)
    }

    @Test func sourceTrustGetDecodesSourcesEnvelope() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses[Self.trustPath] = (200, Data("""
        {"sources":[{"dso_key":2,"source_label":"GarminAPI","metric_class":"daytime_hr_stress",
         "trust_tier":"flagged","note":"Methylphenidate confound — never silently corrected."}]}
        """.utf8))
        let response: SourceTrustResponse = try await dataQualityProvider().client.get(Self.trustPath)
        #expect(response.sources.count == 1)
        #expect(response.sources[0].trustTier == "flagged")
        #expect(response.sources[0].metricClass == "daytime_hr_stress")
        #expect(StubURLProtocol.lastRequest?.url?.path == Self.trustPath)
    }

    /// Card exit criterion: "a 502 → named `HubError`". 502 is the named `.yazioAuthExpired`
    /// contract (`HubError.from`), and it must reach the screen with the hub's `detail` verbatim
    /// rather than being flattened into a generic failure by the fan-out.
    @Test func dataQualityPropagatesNamedHubErrorFromAnyLeg() async throws {
        try stubAllThree()
        StubURLProtocol.responses[Self.trustPath] = (502, Data("{\"detail\":\"upstream down\"}".utf8))
        await #expect(throws: HubError.yazioAuthExpired(detail: "upstream down")) {
            _ = try await self.dataQualityProvider().dataQuality()
        }

        try stubAllThree()
        StubURLProtocol.responses[Self.qualityPath] = (401, Data("{\"detail\":\"bad token\"}".utf8))
        await #expect(throws: HubError.unauthorized) {
            _ = try await self.dataQualityProvider().dataQuality()
        }
    }
}

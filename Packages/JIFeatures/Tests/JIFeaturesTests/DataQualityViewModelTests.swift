import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W5b-L1 (P-data-quality) — the screen's pure banding/sorting/join helpers (ported from the
/// oracle's `app/data-quality.tsx` constants and `src/lib/dataFreshness.ts`), the view model's
/// phase/error discipline, and the two entry seams (`DataQualityAccess`, the badge tap).
@Suite struct DataQualityHelperTests {

    // MARK: banding (verbatim thresholds from data-quality.tsx)

    @Test(arguments: [
        (1.0, DataQualityTone.go), (0.75, .go), (0.7499, .amber), (0.4, .amber), (0.3999, .red), (0.0, .red),
    ])
    func compositeToneBands(composite: Double, expected: DataQualityTone) {
        #expect(dataQualityCompositeTone(composite) == expected)
    }

    @Test func bandsAreTheOracleConstants() {
        #expect(DataQualityBands.greenMin == 0.75)
        #expect(DataQualityBands.amberMin == 0.4)
    }

    @Test func freshnessToneMapsTrafficLight() {
        #expect(dataQualityFreshnessTone(.green) == .go)
        #expect(dataQualityFreshnessTone(.amber) == .amber)
        #expect(dataQualityFreshnessTone(.red) == .red)
    }

    @Test func toneLabelsAreTheOracleLabels() {
        #expect(DataQualityTone.go.label == "Green")
        #expect(DataQualityTone.amber.label == "Amber")
        #expect(DataQualityTone.red.label == "Red")
    }

    @Test func trustLabelFallsBackToRawTier() {
        #expect(dataQualityTrustLabel("trusted") == "Trusted")
        #expect(dataQualityTrustLabel("flagged") == "Flagged")
        #expect(dataQualityTrustLabel("low") == "Low trust")
        #expect(dataQualityTrustLabel("experimental") == "experimental")
    }

    @Test func trustToneMapsTiers() {
        #expect(dataQualityTrustTone("trusted") == .go)
        #expect(dataQualityTrustTone("flagged") == .amber)
        #expect(dataQualityTrustTone("low") == .red)
        #expect(dataQualityTrustTone("anything-else") == .red)
    }

    /// Rule 5: a nil sub-score is an em dash, never "0%".
    @Test func percentNeverRendersZeroForNil() {
        #expect(dataQualityPercent(nil) == "—")
        #expect(dataQualityPercent(0.0) == "0%")
        #expect(dataQualityPercent(0.856) == "86%")
        #expect(dataQualityPercent(1.0) == "100%")
    }

    // MARK: sort + join

    private func row(_ metric: String, composite: Double, source: String = "GarminAPI") -> QualityScoreEntry {
        QualityScoreEntry(
            source: source, dsoKey: 2, metric: metric, metricLabel: metric.capitalized, composite: composite,
            subScores: QualitySubScores(freshness: composite, rangeValidity: nil, trust: nil),
            weightsUsed: ["freshness": 1], componentsAvailable: ["freshness"],
            componentsMissing: ["range_validity", "trust", "provenance"]
        )
    }

    @Test func sortedScoresAreWorstFirstAndStableWithinBand() {
        let rows = [
            row("a", composite: 0.9), row("b", composite: 0.1), row("c", composite: 0.5),
            row("d", composite: 0.2), row("e", composite: 0.8),
        ]
        let sorted = dataQualitySortedScores(rows).map(\.metric)
        #expect(sorted == ["b", "d", "c", "a", "e"])
    }

    @Test func freshnessByKeyJoinsOnSourceAndMetric() {
        let fresh = FreshnessEntry(
            source: "GarminAPI", dsoKey: 2, metric: "sleep", metricLabel: "Sleep", state: .amber,
            lastDate: nil, firstDate: nil, daysStale: 3, cadenceDays: 1, coverageChecked: true,
            gaps: [], gapCount: 0, totalMissingDays: 0
        )
        let byKey = dataQualityFreshnessByKey([fresh])
        #expect(byKey["GarminAPI::sleep"]?.daysStale == 3)
        #expect(byKey["AppleHealth::sleep"] == nil)
        #expect(DataQualityReport.joinKey(source: "GarminAPI", metric: "sleep") == "GarminAPI::sleep")
    }

    // MARK: badge formatters (dataFreshness.ts)

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func syncFreshnessCopyMatchesOracleBoundaries() {
        let iso = { (secondsAgo: TimeInterval) in
            ISO8601DateFormatter().string(from: self.now.addingTimeInterval(-secondsAgo))
        }
        #expect(formatSyncFreshness(nil, now: now) == "Not synced yet")
        #expect(formatSyncFreshness("not a date", now: now) == "Not synced yet")
        #expect(formatSyncFreshness(iso(0), now: now) == "Synced just now")
        #expect(formatSyncFreshness(iso(59), now: now) == "Synced just now")
        #expect(formatSyncFreshness(iso(60), now: now) == "Synced 1m ago")
        #expect(formatSyncFreshness(iso(59 * 60 + 59), now: now) == "Synced 59m ago")
        #expect(formatSyncFreshness(iso(60 * 60), now: now) == "Synced 1h ago")
        #expect(formatSyncFreshness(iso(23 * 3600 + 3599), now: now) == "Synced 23h ago")
        #expect(formatSyncFreshness(iso(24 * 3600), now: now) == "Synced 1d ago")
        #expect(formatSyncFreshness(iso(3 * 24 * 3600 + 5), now: now) == "Synced 3d ago")
    }

    /// The hub's `/ingestion/status` returns a Postgres `str(timestamp)` with a space separator.
    @Test func syncFreshnessAcceptsPostgresTimestampShape() {
        let then = now.addingTimeInterval(-12 * 60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        #expect(formatSyncFreshness(formatter.string(from: then), now: now) == "Synced 12m ago")
    }

    @Test func completenessCopyIsLiteral() {
        #expect(formatTrackedCompleteness(trackedDays: 5, totalDays: 7) == "5/7 days tracked")
        #expect(DataFreshnessInfo(lastSyncISO: nil, trackedDays: 5, totalDays: 7).completenessText == "5/7 days tracked")
        // Rule 5: nothing to say → nothing said, never "0/0 days tracked".
        #expect(DataFreshnessInfo(lastSyncISO: nil).completenessText == nil)
        #expect(DataFreshnessInfo(lastSyncISO: nil, trackedDays: 0, totalDays: 0).completenessText == nil)
    }
}

// MARK: - View model

private struct FakeDataQualityProvider: DataQualityProviding {
    enum Behaviour: Sendable { case report(DataQualityReport), fail(HubError) }
    let behaviour: Behaviour
    func dataQuality() async throws -> DataQualityReport {
        switch behaviour {
        case .report(let r): return r
        case .fail(let e): throw e
        }
    }
}

@Suite @MainActor struct DataQualityViewModelTests {

    @Test func loadsTheFixtureReportWorstFirst() async throws {
        let model = DataQualityViewModel(provider: MockDataProvider())
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.hasLiveResult)
        #expect(model.hubReachable)
        #expect(model.lastError == nil)
        #expect(model.fetchedAt != nil)
        #expect(!model.sortedScores.isEmpty)
        #expect(!model.sourceTrust.isEmpty)
        #expect(model.provenanceGap?.isEmpty == false)

        // Worst first: ranks never decrease down the list.
        let ranks = model.sortedScores.map { dataQualityCompositeTone($0.composite).rank }
        #expect(ranks == ranks.sorted())
        // Every quality row finds its freshness detail (the contract's 1:1 join).
        for entry in model.sortedScores { #expect(model.freshness(for: entry) != nil, "no freshness for \(entry.id)") }
    }

    @Test func emptyReportIsEmptyPhaseNotLoaded() async {
        let empty = DataQualityReport(generatedAt: "now", qualityScore: [], freshness: [], sourceTrust: [], provenanceGap: "note")
        let model = DataQualityViewModel(provider: FakeDataQualityProvider(behaviour: .report(empty)))
        await model.load()
        #expect(model.phase == .empty)
    }

    @Test func networkFailureWithNoCacheIsErrorAndHubUnreachable() async {
        let model = DataQualityViewModel(provider: FakeDataQualityProvider(behaviour: .fail(.network("offline"))))
        await model.load()
        #expect(model.phase == .error("Hub unreachable — is the Mac awake and on the same network?"))
        #expect(model.hubReachable == false)
        #expect(model.lastError == .network("offline"))
        #expect(model.report == nil)
    }

    @Test func namedHubErrorsStayNamedOnTheModel() async {
        let model = DataQualityViewModel(provider: FakeDataQualityProvider(behaviour: .fail(.yazioAuthExpired(detail: "upstream down"))))
        await model.load()
        #expect(model.lastError == .yazioAuthExpired(detail: "upstream down"))
        #expect(model.phase == .error("Hub error: upstream down"))
        #expect(model.hubReachable)

        let unauthorized = DataQualityViewModel(provider: FakeDataQualityProvider(behaviour: .fail(.unauthorized)))
        await unauthorized.load()
        #expect(unauthorized.phase == .error("Hub rejected the token — check Settings › Connection."))
    }

    /// A live failure over a warm cache keeps showing the cached report (behind the staleness
    /// banner) rather than blanking the screen.
    @Test func liveFailureFallsBackToCachedReport() async throws {
        let cache = OfflineCache(db: try AppDatabase.inMemory())
        let warm = DataQualityViewModel(provider: MockDataProvider(), cache: cache)
        await warm.load()
        #expect(warm.phase == .loaded)

        let cold = DataQualityViewModel(provider: FakeDataQualityProvider(behaviour: .fail(.network("offline"))), cache: cache)
        await cold.load()
        #expect(cold.phase == .loaded)
        #expect(cold.report != nil)
        #expect(cold.hubReachable == false)
        #expect(cold.lastError == .network("offline"))
        #expect(cold.hasLiveResult == false)
    }

    // MARK: entry seams

    @Test func accessSeamBuildsAModelOnlyOnceInstalled() {
        let access = DataQualityAccess()
        #expect(access.makeViewModel() == nil)
        access.install(MockDataProvider())
        #expect(access.makeViewModel() != nil)
        access.install(nil)
        #expect(access.makeViewModel() == nil)
    }

    @Test func badgeTapActionOpensDataQuality() {
        var opened = false
        dataFreshnessBadgeTapAction(onOpenDataQuality: { opened = true })()
        #expect(opened)
    }

    @Test func badgeCopyDistinguishesUnknownFromNeverSynced() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let unknown = DataFreshnessBadge(info: nil, now: now)
        #expect(unknown.leadingText == "Data quality")
        let neverSynced = DataFreshnessBadge(info: DataFreshnessInfo(lastSyncISO: nil), now: now)
        #expect(neverSynced.leadingText == "Not synced yet")
        #expect(neverSynced.trailingText == nil)
        let synced = DataFreshnessBadge(
            info: DataFreshnessInfo(lastSyncISO: ISO8601DateFormatter().string(from: now.addingTimeInterval(-120)), trackedDays: 5, totalDays: 7),
            now: now
        )
        #expect(synced.leadingText == "Synced 2m ago")
        #expect(synced.trailingText == "5/7 days tracked")
    }

    @Test func settingsRegistryCarriesTheDataQualitySection() {
        let ids = SettingsRegistry.sections.map(\.id)
        #expect(ids.contains(DataQualitySection.sectionId))
        #expect(SettingsGroup(sortKey: DataQualitySection().sortKey) == .data)
    }
}

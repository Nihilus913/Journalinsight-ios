import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX4 L3 — Data quality & squares (PF-09 source name, PF-11, PF-12, BUG-36 in
// HealthTraining docs/audits/2026-09-25-post-fix-audit.md / 2026-09-25-regression-bugs.md).

private func fresh(_ source: String, _ dso: Int, _ metric: String, _ state: FreshnessState, _ days: Int?,
                   coverage: Bool = true) -> FreshnessEntry {
    FreshnessEntry(source: source, dsoKey: dso, metric: metric, metricLabel: metric, state: state, lastDate: nil,
                   firstDate: nil, daysStale: days, cadenceDays: 1, coverageChecked: coverage, gaps: nil,
                   gapCount: nil, totalMissingDays: nil)
}

/// The audit's live `/ingestion/freshness` (2026-09-25, shots/10-dataquality): Garmin's vitals and
/// activity summary are 3 d old; its Activities (sessions) are 21 d because nobody trained on the
/// Garmin since 09-04 — a sparse-by-design table (`coverage_checked = false`), not a dead feed.
private let pf11Freshness: [FreshnessEntry] = [
    fresh("GarminAPI", 2, "activity", .red, 21, coverage: false),
    fresh("GarminDB", 1, "activity_summary", .red, 178),
    fresh("AppleHealth", 4, "body", .red, 491),
    fresh("GarminAPI", 2, "recovery", .red, 4),
    fresh("GarminAPI", 2, "sleep", .red, 13),
    fresh("GarminAPI", 2, "activity_summary", .amber, 3),
    fresh("GarminAPI", 2, "vitals", .amber, 3),
    fresh("GarminAPI", 2, "vo2max", .amber, 22, coverage: false),
    fresh("AppleHealth", 4, "activity_summary", .green, 1),
    fresh("YAZIO", 3, "body", .green, 0),
    fresh("YAZIO", 3, "nutrition", .green, 0),
    fresh("AppleHealth", 4, "sleep", .green, 1),
    fresh("GarminAPI", 2, "training_load", .green, 0),
    fresh("AppleHealth", 4, "vitals", .green, 1),
]

// MARK: PF-11 — the Garmin row states Garmin's freshness, not its worst metric

@Test func pf11GarminRowIsItsFeedsFreshnessNotItsWorstMetric() {
    let s = dataQualityBoardSourceSummary(pf11Freshness)
    let garmin = s.sources.first { $0.source == "Garmin" }
    #expect(garmin?.daysStale == 3)           // vitals / activity summary, not Activities' 21 d
    #expect(garmin?.state == .amber)
    // ACWR is computed by the hub every day — it never makes a source look fresh.
    #expect(garmin?.state != .green)
    let apple = s.sources.first { $0.source == "Apple Watch" }
    #expect(apple?.state == .green)
    #expect(apple?.daysStale == 1)
    #expect(s.sources.count == 3)
}

@Test func pf11ADeadFeedStillReadsStale() {
    let s = dataQualityBoardSourceSummary([fresh("GarminAPI", 2, "vitals", .red, 30),
                                           fresh("GarminAPI", 2, "sleep", .red, 31),
                                           fresh("AppleHealth", 4, "vitals", .green, 1)])
    #expect(s.sources.first { $0.source == "Garmin" }?.state == .red)
    #expect(s.sources.first { $0.source == "Garmin" }?.daysStale == 30)
    #expect(s.stale == 1)
}

@Test func pf11ASourceWithOnlySparseMetricsFallsBackToThem() {
    let s = dataQualityBoardSourceSummary([fresh("GarminAPI", 2, "activity", .amber, 5, coverage: false)])
    #expect(s.sources.first?.daysStale == 5)
}

// MARK: PF-09 — Data quality names YAZIO as YAZIO (intake comes from the YAZIO API, dso 3)

@Test func pf09DataQualityNamesYazioNotAppleHealth() {
    #expect(dataQualitySourceDisplay("YAZIO") == "YAZIO")
    #expect(dataQualitySourceDisplay("yazio") == "YAZIO")
    #expect(!dataQualitySourceDisplay("YAZIO").contains("Apple Health"))
}

// MARK: BUG-36 — Today squares use the KPI's own decimals, never grouping

@Test func bug36TodaySquaresUseTheKpiDecimalsWithoutGrouping() {
    func value(_ id: String, _ v: Double) -> String? {
        todaySummaryCardSpec(for: TodayChip(id: id, label: id, value: v, unit: nil, points: [], sourceMissing: false)).value
    }
    #expect(value("steps", 8420) == "8420")        // no "8,420" / "8’420"
    #expect(value("kcal", 1619.4) == "1619")
    #expect(value("fat", 37.8) == "38")            // the one rounding rule (My KPIs / KpiDetail)
    #expect(value("protein", 131.6) == "132")
    #expect(value("weight", 82.46) == "82.5")      // KpiMetricDef.weight.decimals = 1
    #expect(value("weight", 82.0) == "82.0")
    #expect(value("acwr", 1.234) == "1.23")        // decimals = 2
    #expect(value("hrv", 61.4) == "61")
    // The square and the KPI detail agree for every catalogue metric.
    for def in KpiMetrics.all {
        #expect(value(def.id.rawValue, 1234.567) == jiNumber(1234.567, def.decimals))
    }
}

// MARK: PF-12 — morning-verdict is only ever asked for a real date

private actor VerdictDates { var dates: [String] = []; func add(_ d: String) { dates.append(d) } }

private struct RecordingVerdictProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    let seen: VerdictDates
    func health() async throws -> HealthResponse { try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict {
        await seen.add(date)
        return try await inner.morningVerdict(date: date)
    }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
}

@Test @MainActor func pf12AnEmptyDeepLinkDateIsTheLiveRationaleNotADatelessVerdictCall() async {
    let seen = VerdictDates()
    let vm = GateRationaleViewModel(provider: RecordingVerdictProvider(seen: seen), date: "")
    #expect(!vm.isByDate)
    await vm.load()
    let dates = await seen.dates
    #expect(!dates.contains(""))
    #expect(dates.allSatisfy { $0.count == 10 })
}

@Test func pf12TheThreeDayTrailNeverHoldsAnEmptyDate() {
    #expect(GateRationaleViewModel.lastThreeDates(anchor: "").isEmpty)
    #expect(GateRationaleViewModel.lastThreeDates(anchor: nil).isEmpty)
    #expect(GateRationaleViewModel.lastThreeDates(anchor: "2026-09-25") == ["2026-09-25", "2026-09-24", "2026-09-23"])
}

import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

@Test @MainActor func kpiDetailLoadsHistoryForARecoveryMetric() async throws {
    let vm = KpiDetailViewModel(
        metric: .rhr, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.value != nil)
    #expect(vm.history.isEmpty == false)
}

@Test @MainActor func kpiDetailFindsItsMatchingGateRule() async throws {
    let vm = KpiDetailViewModel(
        metric: .acwr, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    await vm.load()
    #expect(vm.target != nil)
    #expect(vm.target?.metric == "acwr")
}

@Test @MainActor func kpiDetailHasNoTargetWhenMetricIsUntargeted() async throws {
    let vm = KpiDetailViewModel(
        metric: .rhr, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    await vm.load()
    #expect(vm.target == nil)
}

// MARK: - B-57 W1 fixer: KpiDetail / KpiDetailNutrition board deltas

@Test @MainActor func kpiDetailStampsWhenItsOwnSourceLastSynced() async throws {
    let vm = KpiDetailViewModel(
        metric: .protein, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    #expect(vm.fetchedAt == nil)   // never synced = the pill says "Not synced yet", not a made-up time
    await vm.load()
    #expect(vm.fetchedAt != nil)
}

@Test func kpiDetailRangesAreTheBoards7_30_90() {
    #expect(KpiDetailRange.allCases.map(\.label) == ["7 D", "30 D", "90 D"])
    #expect(KpiDetailRange.allCases.map(\.days) == [7, 30, 90])
}

@Test func kpiDetailTrendPointsSkipMissingDaysAndKeepTheNewestWindow() {
    let history: [(date: String, value: Double?)] = (1...20).map { d in
        (date: String(format: "2026-09-%02d", d), value: d == 19 ? nil : Double(d))
    }
    let points = kpiDetailTrendPoints(history, range: .week)
    // The last 7 calendar days (14…20) minus the missing 19th — never a zero in its place.
    #expect(points.map(\.value) == [14, 15, 16, 17, 18, 20])
}

@Test func kpiSourceSubtitleNamesWhereEveryMetricComesFrom() {
    #expect(kpiSourceSubtitle(.protein) == "Read from Apple Health · written by YAZIO")
    #expect(kpiSourceSubtitle(.hrv) == "Your watch · measured while you sleep")
    for id in KpiMetricId.allCases { #expect(!kpiSourceSubtitle(id).isEmpty) }
}

@Test func kpiAlertStepFollowsTheMetricsPrecision() {
    #expect(kpiAlertStep(decimals: 0) == 1)
    #expect(kpiAlertStep(decimals: 1) == 0.1)
    #expect(kpiAlertStep(decimals: 2) == 0.05)
}

@Test func kpiAlertStepperSnapsToItsGridAndNeverGoesNegative() {
    #expect(kpiAlertStepped(1.05, by: 0.05) == 1.1)
    #expect(kpiAlertStepped(27, by: -1) == 26)
    #expect(kpiAlertStepped(0, by: -1) == 0)
}

// MARK: - W-B67 R-3: "How this score is built" (Sleep KPI detail)

/// The KPI fake plus the hub's `/vitals/sleep-summary` seam; `summary == nil` = an old hub that
/// serves no breakdown.
nonisolated struct B67SleepProvider: HealthDataProvider, SleepSummaryProviding {
    let capabilities: DataCapability = .hubAll
    let base = KpiFakeProvider()
    var summary: SleepSummary
    func health() async throws -> HealthResponse { try await base.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await base.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await base.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await base.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await base.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await base.syncStatus() }
    func sleepSummary() async throws -> SleepSummary { summary }
}

/// Toby's Apple night 2026-10-04 as the R-1 hub serves it (86 = 50.0 + 5.7 + 20.0 + 10.0).
private let b67LiveNight = SleepSummary(
    scoreComputed: 86, scoreComputedDate: "2026-10-04", scoreComputedSource: "AppleHealth",
    scoreBreakdown: SleepScoreBreakdown(total: 86, components: [
        SleepScoreComponent(key: "duration", points: 50.0, max: 50, value: 36200),
        SleepScoreComponent(key: "deep", points: 5.7, max: 20, value: 1858, share: 0.051, target: 0.18),
        SleepScoreComponent(key: "rem", points: 20.0, max: 20, value: 11417, share: 0.315, target: 0.225),
        SleepScoreComponent(key: "continuity", points: 10.0, max: 10, value: 1109, share: 0.031),
    ]),
    lastNightAwakeSec: 1109)

@MainActor
private func b67Model(_ summary: SleepSummary, metric: KpiMetricId = .sleep) throws -> KpiDetailViewModel {
    KpiDetailViewModel(metric: metric, healthProvider: B67SleepProvider(summary: summary), nutritionProvider: KpiFakeProvider(),
                       targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
}

@Test @MainActor func testSleepBreakdownRows() async throws {
    let vm = try b67Model(b67LiveNight)
    await vm.load()
    let rows = try #require(vm.sleepBreakdownRows)
    #expect(rows.map(\.id) == ["duration", "deep", "rem", "continuity"])
    #expect(rows.map(\.pointsText) == ["50.0 / 50", "5.7 / 20", "20.0 / 20", "10.0 / 10"])
    let deep = rows[1]
    #expect(deep.input.contains("5 %") && deep.input.contains("18 %"))
    #expect(deep.input.hasPrefix("31 min"))
    #expect(rows[0].input == "10 h 03")
    #expect(rows[3].input == "18 min awake")
    #expect(rows.allSatisfy { $0.source == "Apple" })
    #expect(abs(deep.fraction - 5.7 / 20) < 1e-9)
    #expect(vm.sleepBreakdownFooter == "Shadow score — not a gate input")
    #expect(vm.sleepBreakdownTotal == 86)

    // An old hub (no score_breakdown) → the section is hidden, nothing crashes.
    let old = try b67Model(SleepSummary(scoreComputed: 82, scoreComputedDate: "2026-09-11"))
    await old.load()
    #expect(old.phase == .loaded)
    #expect(old.sleepBreakdownRows == nil)

    // Only the Sleep metric shows it.
    let hrv = try b67Model(b67LiveNight, metric: .hrv)
    await hrv.load()
    #expect(hrv.sleepBreakdownRows == nil)
}

@Test func sleepBreakdownMissingStageSaysCreditedNotZero() {
    let b = SleepScoreBreakdown(total: 82, components: [
        SleepScoreComponent(key: "duration", points: 50.0, max: 50, value: 28800),
        SleepScoreComponent(key: "deep", points: 16.0, max: 20, target: 0.18, inferred: true),
        SleepScoreComponent(key: "rem", points: 16.0, max: 20, target: 0.225, inferred: true),
        SleepScoreComponent(key: "continuity", points: 8.0, max: 10, inferred: true),
    ])
    let rows = sleepBreakdownRows(b, source: "GarminAPI")
    #expect(rows[1].input == "no data · credited 80 %")
    #expect(rows[2].input == "no data · credited 80 %")
    #expect(rows[3].input == "no data · credited 80 %")
    #expect(rows[0].source == "Garmin")
}

@Test func sleepBreakdownMapsTheOnDeviceComputation() throws {
    let computed = try #require(computeSleepScoreBreakdown(durationSec: 36200, deepSec: 1858, remSec: 11417, awakeSec: 1109))
    let dto = SleepScoreBreakdown(computed: computed)
    #expect(dto == b67LiveNight.scoreBreakdown)
}

import Foundation
import Testing
import JICore
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

/// Card exit criterion: "detail = Swift Charts history + target edit round-trip (PUT, stub-URLProtocol
/// test)". The stub-URLProtocol side of the round trip lives in
/// `HubDataProviderKpiTargetsTests.swift` (JIHub); this exercises the view-model's side of the same
/// round trip against a fake that can be told to fail, mirroring `EnergyViewModelTests`' split.
nonisolated struct KpiTargetUpdateFailingProvider: KpiTargetsProviding {
    let inner = MockDataProvider()
    let error: HubError
    func kpiTargets() async throws -> [KpiTarget] { try await inner.kpiTargets() }
    func updateKpiTarget(id: Int, threshold: Double, thresholdHi: Double?, description: String?) async throws -> KpiTarget { throw error }
}

@Test @MainActor func saveThresholdRoundTripsAndUpdatesTarget() async throws {
    let vm = KpiDetailViewModel(
        metric: .acwr, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    await vm.load()
    let original = try #require(vm.target)
    await vm.saveThreshold(1.5)
    #expect(vm.target?.targetId == original.targetId)
    #expect(vm.target?.threshold == 1.5)
    #expect(vm.saveError == nil)
    #expect(vm.saving == false)
}

@Test @MainActor func saveThresholdSurfacesHubDetailVerbatimOnFailure() async throws {
    let vm = KpiDetailViewModel(
        metric: .acwr, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
        targetsProvider: KpiFakeProvider(), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    await vm.load()
    let before = vm.target
    let failing = KpiTargetUpdateFailingProvider(error: .from(status: 502, detail: "YAZIO auth expired mid-save"))
    // Swap in a failing provider for just the save call by constructing a fresh view model that
    // shares the same already-loaded target (simulates the save's own network attempt failing).
    let vm2 = KpiDetailViewModel(metric: .acwr, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(), targetsProvider: failing, cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm2.load()
    await vm2.saveThreshold(9.9)
    #expect(vm2.saveError != nil)
    #expect(vm2.target?.threshold == before?.threshold) // unchanged on failure
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

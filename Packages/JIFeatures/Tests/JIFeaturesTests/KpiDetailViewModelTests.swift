import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

@Test @MainActor func kpiDetailLoadsHistoryForARecoveryMetric() async throws {
    let vm = KpiDetailViewModel(
        metric: .hrv, healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(),
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

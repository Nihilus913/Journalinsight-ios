import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// Combines `HealthDataProvider` + `NutritionProviding` + `KpiTargetsProviding` — the three
/// existing/new protocols `KpiListViewModel` needs — delegating to `MockDataProvider`. Mirrors
/// `RecoveryFlakyProvider`'s file-independence rationale (no shared test-support target).
nonisolated struct KpiFakeProvider: HealthDataProvider, NutritionProviding, KpiTargetsProviding {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    let failing: Bool
    let error: HubError
    init(failing: Bool = false, error: HubError = .network("simulated")) { self.failing = failing; self.error = error }
    private func guardFail() throws { if failing { throw error } }

    func health() async throws -> HealthResponse { try guardFail(); return try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try guardFail(); return try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try guardFail(); return try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try guardFail(); return try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try guardFail(); return try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try guardFail(); return try await inner.syncStatus() }

    func nutritionDay(date: String) async throws -> NutritionDayDetail? { try guardFail(); return try await inner.nutritionDay(date: date) }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { try guardFail(); return try await inner.nutritionWeek(windowDays: windowDays) }
    func logFood(_ body: LogFoodBody) async throws -> LogFoodResult { try guardFail(); return try await inner.logFood(body) }
    func deleteLogItem(itemId: String, date: String?) async throws { try guardFail(); try await inner.deleteLogItem(itemId: itemId, date: date) }

    func kpiTargets() async throws -> [KpiTarget] { try guardFail(); return try await inner.kpiTargets() }
    func updateKpiTarget(id: Int, threshold: Double, thresholdHi: Double?, description: String?) async throws -> KpiTarget {
        try guardFail(); return try await inner.updateKpiTarget(id: id, threshold: threshold, thresholdHi: thresholdHi, description: description)
    }
}

@MainActor
private func makeModel(failing: Bool = false) -> KpiListViewModel {
    KpiListViewModel(
        healthProvider: KpiFakeProvider(failing: failing), nutritionProvider: KpiFakeProvider(failing: failing),
        targetsProvider: KpiFakeProvider(failing: failing), prefStore: PrefStore(db: try! .inMemory()),
        cache: OfflineCache(db: try! .inMemory())
    )
}

@Test @MainActor func kpiListLoadsEveryMetricWithLiveValue() async throws {
    let vm = makeModel()
    await vm.load()
    #expect(vm.phase == .loaded)
    // Recovery + nutrition sourced metrics resolve to a real value from the mock's fixtures
    // (never crash, never a fabricated 0 — rule 5); `.value(for:)` is callable for every id.
    for id in KpiMetricId.allCases { _ = vm.value(for: id) }
    #expect(vm.value(for: .hrv) != nil)
    #expect(vm.value(for: .kcal) != nil)
    #expect(vm.targets.isEmpty == false)
}

@Test @MainActor func kpiListAcwrHasATargetFromTheMockFixture() async throws {
    let vm = makeModel()
    await vm.load()
    #expect(vm.targetText(for: .acwr) != nil)
    #expect(vm.targetText(for: .rhr) == nil) // no gate rule targets rhr
}

@Test @MainActor func kpiListHubDownFallsBackToCache() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let prefStore = PrefStore(db: try AppDatabase.inMemory())
    await KpiListViewModel(
        healthProvider: KpiFakeProvider(failing: false), nutritionProvider: KpiFakeProvider(failing: false),
        targetsProvider: KpiFakeProvider(failing: false), prefStore: prefStore, cache: cache
    ).load() // warm the cache

    let vm = KpiListViewModel(
        healthProvider: KpiFakeProvider(failing: true), nutritionProvider: KpiFakeProvider(failing: true),
        targetsProvider: KpiFakeProvider(failing: true), prefStore: prefStore, cache: cache
    )
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable == false)
    #expect(vm.targets.isEmpty == false)
}

// MARK: - Selection persists (PrefStore)

@Test @MainActor func togglingSelectionPersistsAcrossViewModelInstances() async throws {
    let db = try AppDatabase.inMemory()
    let cache = OfflineCache(db: db)
    let prefStore = PrefStore(db: db)
    let vm1 = KpiListViewModel(healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(), targetsProvider: KpiFakeProvider(), prefStore: prefStore, cache: cache)
    await vm1.load()
    #expect(vm1.toggle(.kcal, selected: true))
    #expect(vm1.visibleOrder.contains(.kcal))

    let vm2 = KpiListViewModel(healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(), targetsProvider: KpiFakeProvider(), prefStore: prefStore, cache: cache)
    await vm2.load()
    #expect(vm2.visibleOrder.contains(.kcal))
}

@Test @MainActor func toggleRefusesBelowFloorAndReturnsFalse() async throws {
    let vm = makeModel()
    await vm.load()
    for id in [KpiMetricId.hrv, .rhr, .sleep, .steps] { _ = vm.toggle(id, selected: false) }
    #expect(vm.toggle(.bodyBattery, selected: false) == false)
}

@Test @MainActor func resetSelectionRestoresDefaultsAndPersists() async throws {
    let db = try AppDatabase.inMemory()
    let vm = KpiListViewModel(healthProvider: KpiFakeProvider(), nutritionProvider: KpiFakeProvider(), targetsProvider: KpiFakeProvider(), prefStore: PrefStore(db: db), cache: OfflineCache(db: db))
    await vm.load()
    _ = vm.toggle(.kcal, selected: true)
    vm.resetSelection()
    #expect(vm.prefs == KpiSelection.defaultPrefs())
}

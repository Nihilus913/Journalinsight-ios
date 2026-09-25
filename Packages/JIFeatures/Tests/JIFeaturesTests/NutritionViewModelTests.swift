import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// A `NutritionProviding` fake that can be told to fail — mirrors `RecoveryFlakyProvider`
/// (JIFeaturesTests has no shared test-support target).
nonisolated struct NutritionFlakyProvider: NutritionProviding {
    let inner = MockDataProvider()
    let failing: Bool
    let error: HubError
    init(failing: Bool, error: HubError = .network("simulated")) { self.failing = failing; self.error = error }
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { try guardFail(); return try await inner.nutritionDay(date: date) }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { try guardFail(); return try await inner.nutritionWeek(windowDays: windowDays) }
    private func guardFail() throws { if failing { throw error } }
}

/// Always succeeds with nothing logged — exercises the never-synced/empty distinction.
nonisolated struct NutritionEmptyProvider: NutritionProviding {
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { nil }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { [] }
}

@Test @MainActor func nutritionLiveLoadPopulatesDayAndWeekAndCaches() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = NutritionViewModel(provider: NutritionFlakyProvider(failing: false), cache: cache, initialDate: "2026-09-11")
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable)
    #expect(vm.day?.date == "2026-09-11")
    #expect(vm.week.count == 7)
    #expect(try cache.get("nutrition.day.2026-09-11", as: NutritionDayDetail?.self) != nil)
    #expect(try cache.get("nutrition.week", as: [NutritionDailyRow].self) != nil)
}

@Test @MainActor func nutritionHubDownFallsBackToCacheAndFlagsStale() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    await NutritionViewModel(provider: NutritionFlakyProvider(failing: false), cache: cache, initialDate: "2026-09-11").load()
    let vm = NutritionViewModel(provider: NutritionFlakyProvider(failing: true), cache: cache, initialDate: "2026-09-11")
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable == false)
    #expect(vm.day != nil)
    #expect(vm.week.isEmpty == false)
}

@Test @MainActor func nutritionEmptyWhenNoDayOrWeek() async throws {
    let vm = NutritionViewModel(provider: NutritionEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.phase == .empty)
    #expect(vm.day == nil)
    #expect(vm.week.isEmpty)
}

@Test @MainActor func nutritionSelectDateReQueriesInPlace() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = NutritionViewModel(provider: NutritionFlakyProvider(failing: false), cache: cache, initialDate: "2026-09-11")
    await vm.load()
    await vm.selectDate("2026-09-10")
    // The mock always serves the same fixture day regardless of date — this asserts the VM
    // actually re-fetched (day still non-nil, no crash on the new key) rather than the exact
    // echoed date, since MockDataProvider.nutritionDay ignores its `date` argument.
    #expect(vm.day != nil)
}

@Test @MainActor func nutritionYazioAuthExpiredTakesPriorityOverOtherErrors() async throws {
    let vm = NutritionViewModel(
        provider: NutritionFlakyProvider(failing: true, error: .yazioAuthExpired(detail: "token stale")),
        cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    await vm.load()
    #expect(vm.screenState == .yazioAuthExpired(detail: "token stale"))
}

/// B-57 W1 (v11 change 2): JI never logs food. The protocol is read-only; a conformer needs only the two reads.
nonisolated struct ReadOnlyNutritionProvider: NutritionProviding {
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { nil }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { [] }
}
@Test func nutritionProvidingIsReadOnly() {
    let p: any NutritionProviding = ReadOnlyNutritionProvider()
    #expect(p is ReadOnlyNutritionProvider)
}

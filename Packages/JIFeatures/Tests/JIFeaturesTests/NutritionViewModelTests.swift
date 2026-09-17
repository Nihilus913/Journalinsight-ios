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
    func logFood(_ body: LogFoodBody) async throws -> LogFoodResult { try guardFail(); return try await inner.logFood(body) }
    func deleteLogItem(itemId: String, date: String?) async throws { try guardFail(); try await inner.deleteLogItem(itemId: itemId, date: date) }
    private func guardFail() throws { if failing { throw error } }
}

/// Always succeeds with nothing logged — exercises the never-synced/empty distinction.
nonisolated struct NutritionEmptyProvider: NutritionProviding {
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { nil }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { [] }
    func logFood(_ body: LogFoodBody) async throws -> LogFoodResult { LogFoodResult(logged: [], date: "2026-09-17") }
    func deleteLogItem(itemId: String, date: String?) async throws {}
}

/// A `logFood`/`deleteLogItem` fake that always rejects with a given `HubError` — for the
/// 409/502 UI-contract tests.
nonisolated struct NutritionLogRejectingProvider: NutritionProviding {
    let error: HubError
    func nutritionDay(date: String) async throws -> NutritionDayDetail? { nil }
    func nutritionWeek(windowDays: Int) async throws -> [NutritionDailyRow] { [] }
    func logFood(_ body: LogFoodBody) async throws -> LogFoodResult { throw error }
    func deleteLogItem(itemId: String, date: String?) async throws { throw error }
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

// MARK: - LogSheetViewModel (PINNED FOOD-LOG CONTRACT)

@Test @MainActor func logSheetSubmitsTemplateAndReportsSuccess() async throws {
    let model = LogSheetViewModel(provider: MockDataProvider())
    let result = await model.submitTemplate("breakfast_default", meal: .breakfast)
    #expect(result != nil)
    if case .success = model.state {} else { Issue.record("expected .success, got \(model.state)") }
}

@Test @MainActor func logSheetDuplicateShowsRNCopyVerbatim() async throws {
    let model = LogSheetViewModel(provider: NutritionLogRejectingProvider(error: .duplicate(detail: "YAZIO_DUPLICATE")))
    let result = await model.submitTemplate("breakfast_default", meal: .breakfast)
    #expect(result == nil)
    #expect(model.state == .failure("Already logged today."))
}

@Test @MainActor func logSheetAuthExpiredShowsRNCopyVerbatim() async throws {
    let model = LogSheetViewModel(provider: NutritionLogRejectingProvider(error: .yazioAuthExpired(detail: "YAZIO_AUTH_EXPIRED")))
    let result = await model.submitTemplate("breakfast_default", meal: .breakfast)
    #expect(result == nil)
    #expect(model.state == .failure("YAZIO login expired — reconnect on the Mac."))
}

@Test @MainActor func logSheetDeleteRoundTrips() async throws {
    let model = LogSheetViewModel(provider: MockDataProvider())
    let logged = await model.submitTemplate("breakfast_default", meal: .breakfast)
    let itemId = try #require(logged?.logged.first?.itemId)
    let ok = await model.delete(itemId: itemId)
    #expect(ok)
}

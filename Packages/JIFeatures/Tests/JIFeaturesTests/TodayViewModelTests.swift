import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// A provider that can be told to fail, to exercise the cache fallback.
nonisolated struct FlakyProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    let inner = MockDataProvider()
    let failing: Bool
    func health() async throws -> HealthResponse { try guardFail(); return try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try guardFail(); return try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try guardFail(); return try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try guardFail(); return try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try guardFail(); return try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try guardFail(); return try await inner.syncStatus() }
    private func guardFail() throws { if failing { throw HubError.network("simulated") } }
}

/// A provider whose failure mode can be flipped between calls, to exercise `refresh()` after an
/// already-successful `load()` — an `actor` (not `@unchecked Sendable`) gives it safely mutable state.
actor ToggleProvider: HealthDataProvider {
    nonisolated let capabilities: DataCapability = .hubAll
    private nonisolated let inner = MockDataProvider()
    private var failing: Bool
    init(failing: Bool) { self.failing = failing }
    func setFailing(_ value: Bool) { failing = value }
    func health() async throws -> HealthResponse { try guardFail(); return try await inner.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try guardFail(); return try await inner.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try guardFail(); return try await inner.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try guardFail(); return try await inner.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try guardFail(); return try await inner.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try guardFail(); return try await inner.syncStatus() }
    private func guardFail() throws { if failing { throw HubError.network("simulated") } }
}

@Test @MainActor func liveLoadPopulatesAndCaches() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = TodayViewModel(provider: FlakyProvider(failing: false), cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable)
    #expect(vm.chips.map(\.label) == ["HRV", "RHR", "Sleep", "Steps"])
    #expect(try cache.get("today.morning", as: MorningResponse.self) != nil)
}

@Test @MainActor func hubDownFallsBackToCacheAndFlagsStale() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    await TodayViewModel(provider: FlakyProvider(failing: false), cache: cache).load()   // warm the cache
    let vm = TodayViewModel(provider: FlakyProvider(failing: true), cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable == false)
    #expect(vm.fetchedAt != nil)
    #expect(vm.morning != nil)
}

@Test @MainActor func hubDownWithEmptyCacheIsError() async throws {
    let vm = TodayViewModel(provider: FlakyProvider(failing: true), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect({ if case .error = vm.phase { true } else { false } }())
}

@Test @MainActor func refreshAfterSuccessfulLoadFlipsReachabilityButKeepsMorning() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let provider = ToggleProvider(failing: false)
    let vm = TodayViewModel(provider: provider, cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable)
    #expect(vm.morning != nil)

    await provider.setFailing(true)
    await vm.refresh()

    #expect(vm.morning != nil)
    #expect(vm.hubReachable == false)
    #expect(vm.phase == .loaded)
}

@Test func todayRowFallbackMatchesRN() {
    func row(_ date: String, kcal: Double?, protein: Double?, steps: Double?) -> DailyKpiRow {
        var r = try! JSON.decoder.decode(DailyKpiRow.self, from: Data("{\"date\":\"\(date)\"}".utf8))
        r.values = ["kcal_consumed": kcal, "protein_g": protein, "steps": steps]
        return r
    }
    let daily = [row("2026-09-12", kcal: 0, protein: nil, steps: 312), row("2026-09-11", kcal: 1810, protein: 170, steps: 8486)]
    let resolved = resolveTodayRow(daily)
    #expect(resolved.row?.date == "2026-09-11")
    #expect(resolved.stale)
}

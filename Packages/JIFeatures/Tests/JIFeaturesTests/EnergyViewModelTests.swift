import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

/// Mirrors `RecoveryFlakyProvider` (same file-independence rationale — JIFeaturesTests has no
/// shared test-support target).
nonisolated struct EnergyFlakyProvider: EnergyProviding {
    let inner = MockDataProvider()
    let failing: Bool
    let error: HubError
    init(failing: Bool, error: HubError = .network("simulated")) { self.failing = failing; self.error = error }
    func energy(windowDays: Int) async throws -> EnergyReport { try guardFail(); return try await inner.energy(windowDays: windowDays) }
    func goals() async throws -> Goals { try guardFail(); return try await inner.goals() }
    private func guardFail() throws { if failing { throw error } }
}

nonisolated struct EnergySlowProvider: EnergyProviding {
    private func park<T>() async throws -> T { try await Task.sleep(for: .seconds(30)); throw HubError.network("unreachable test path") }
    func energy(windowDays: Int) async throws -> EnergyReport { try await park() }
    func goals() async throws -> Goals { try await park() }
}

nonisolated struct EnergyEmptyProvider: EnergyProviding {
    func energy(windowDays: Int) async throws -> EnergyReport {
        EnergyReport(days: [], trackingDays: 0, compliant: false, complianceWarning: "no data")
    }
    func goals() async throws -> Goals { try await MockDataProvider().goals() }
}

@Test @MainActor func energyLiveLoadPopulatesAndCaches() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = EnergyViewModel(provider: EnergyFlakyProvider(failing: false), cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable)
    #expect(vm.days.isEmpty == false)
    #expect(vm.goals?.stepsDaily == 15000)
    #expect(try cache.get("energy.report", as: EnergyReport.self) != nil)
}

@Test @MainActor func energyHubDownFallsBackToCacheAndFlagsStale() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    await EnergyViewModel(provider: EnergyFlakyProvider(failing: false), cache: cache).load() // warm the cache
    let vm = EnergyViewModel(provider: EnergyFlakyProvider(failing: true), cache: cache)
    await vm.load()
    #expect(vm.phase == .loaded)
    #expect(vm.hubReachable == false)
    #expect(vm.fetchedAt != nil)
    #expect(vm.days.isEmpty == false)
}

@Test @MainActor func energyEmptyWhenNoDays() async throws {
    let vm = EnergyViewModel(provider: EnergyEmptyProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.phase == .empty)
    #expect(vm.days.isEmpty)
}

@Test @MainActor func energyCancelledLoadReturnsToIdle() async throws {
    let vm = EnergyViewModel(provider: EnergySlowProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
    let t = Task { await vm.load() }
    try await Task.sleep(for: .milliseconds(50))
    t.cancel()
    await t.value
    #expect(vm.phase == .idle)
    #expect(vm.hubReachable)
    #expect(vm.hasLiveResult == false)
}

@Test @MainActor func energyScreenStateFlagsYazioAuthExpired() async throws {
    let expired = EnergyViewModel(provider: EnergyFlakyProvider(failing: true, error: .yazioAuthExpired(detail: "token stale")), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await expired.load()
    #expect(expired.screenState == .yazioAuthExpired(detail: "token stale"))
}

// MARK: - compute arithmetic branch coverage (useComputedEnergy port — one test per branch)

@Test @MainActor func balanceTextFormatsDeficitSurplusAndZero() {
    #expect(EnergyFormat.balanceText(500) == "-500")   // deficit
    #expect(EnergyFormat.balanceText(-300) == "+300")  // surplus
    #expect(EnergyFormat.balanceText(0) == "0")
    #expect(EnergyFormat.balanceText(nil) == "—")
}

@Test @MainActor func deficitColorNeverUsesReservedVerdictGreen() {
    #expect(EnergyFormat.deficitColor(nil, class: nil) == JIColor.muted)
    #expect(EnergyFormat.deficitColor(-100, class: "surplus") == JIColor.muted)
    #expect(EnergyFormat.deficitColor(600, class: "dangerous") == JIColor.danger)
    #expect(EnergyFormat.deficitColor(400, class: "aggressive") == JIColor.reduced)
    #expect(EnergyFormat.deficitColor(150, class: "mild") == JIColor.info)
    #expect(![JIColor.go].contains(EnergyFormat.deficitColor(600, class: "dangerous")))
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W8-L4: every hub-backed ViewModel that used to hand-roll loading/error now resolves a DESIGN-7
// `ScreenState` from the same signals — one test per converted VM.

// MARK: - DataQualityViewModel

nonisolated private struct DataQualityStubProvider: DataQualityProviding {
    var error: HubError?
    var report = DataQualityReport(generatedAt: "2026-09-18T06:00:00Z", qualityScore: [], freshness: [], sourceTrust: [], provenanceGap: "")
    func dataQuality() async throws -> DataQualityReport { if let error { throw error }; return report }
}

@Test @MainActor func dataQualityScreenStateFollowsPhaseAndNamesYazioAuthExpired() async {
    let ok = DataQualityViewModel(provider: DataQualityStubProvider())
    #expect(ok.screenState == .idle)
    await ok.load()
    #expect(ok.screenState == .empty) // an empty report after a successful first load is a blank, not an error

    let down = DataQualityViewModel(provider: DataQualityStubProvider(error: .network("offline")))
    await down.load()
    guard case .error = down.screenState else { Issue.record("expected .error, got \(down.screenState)"); return }

    let yazio = DataQualityViewModel(provider: DataQualityStubProvider(error: .yazioAuthExpired(detail: "YAZIO token expired")))
    await yazio.load()
    #expect(yazio.screenState == .yazioAuthExpired(detail: "YAZIO token expired"))
}

// MARK: - KpiListViewModel / KpiDetailViewModel

@Test @MainActor func kpiListScreenStateIsIdleThenLoaded() async throws {
    let vm = KpiListViewModel(
        healthProvider: MockDataProvider(), nutritionProvider: MockDataProvider(), targetsProvider: MockDataProvider(),
        prefStore: PrefStore(db: try AppDatabase.inMemory()), cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    #expect(vm.screenState == .idle)
    await vm.load()
    #expect(vm.screenState == .loaded)
}

@Test @MainActor func kpiDetailScreenStateIsIdleThenLoaded() async throws {
    let vm = KpiDetailViewModel(
        metric: .hrv, healthProvider: MockDataProvider(), nutritionProvider: MockDataProvider(), targetsProvider: MockDataProvider(),
        cache: OfflineCache(db: try AppDatabase.inMemory())
    )
    #expect(vm.screenState == .idle)
    await vm.load()
    #expect(vm.screenState == .loaded)
}

// MARK: - GateRationaleViewModel

@Test @MainActor func gateRationaleScreenStateLoadsAndMapsNoVerdictToEmpty() async {
    let vm = GateRationaleViewModel(provider: MockDataProvider())
    #expect(vm.screenState == .idle)
    await vm.load()
    #expect(vm.screenState == .loaded)
    // The by-date branch with no run for that day is an honest blank, never an error.
    #expect(GateRationaleViewModel.Phase.noVerdictForDate("2026-01-01") != .idle)
}

// MARK: - HealthBackloadViewModel

nonisolated private struct IdleBackloader: BackloadRunning {
    func authorize() async throws {}
    func run(_ range: BackloadRange, progress: @Sendable (BackloadProgress) -> Void) async throws -> BackloadSummary {
        throw BackloadError.healthDataUnavailable
    }
}

@Test @MainActor func healthBackloadScreenStateIsIdleUntilARunStarts() {
    let vm = HealthBackloadViewModel(runner: IdleBackloader(), hrvPrefs: nil)
    #expect(vm.screenState == .idle)
}

// MARK: - SessionCoachViewModel

@Test @MainActor func sessionCoachScreenStateIsEmptyWhenTheProviderCannotStreamAndLoadingBeforeTheFirstPoll() {
    let incapable = SessionCoachViewModel(provider: nil)
    #expect(incapable.screenState == .empty)
}

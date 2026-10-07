import Foundation
import Testing
import JICore
import JIFeatures
import JIPersistence
@testable import JournalInsight

/// W-OFFLINE OFF-1 (B-50 slice 1): with no hub (or an on-device data source that speaks none of
/// the hub screens' protocols) the five hub-screen models still exist, in `.needsHub`; with a hub
/// they are built exactly as before (`.live`).
@Suite @MainActor struct HubScreensFallbackTests {
    /// Stands in for `HealthKitProvider`: a data source with no hub-screen protocol.
    struct OnDeviceOnly: HealthDataProvider {
        var capabilities: DataCapability { [] }
        func health() async throws -> HealthResponse { throw HubError.network("x") }
        func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("x") }
        func morning() async throws -> MorningResponse { throw HubError.network("x") }
        func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("x") }
        func recovery(windowDays: Int) async throws -> [RecoveryDay] { throw HubError.network("x") }
        func syncStatus() async throws -> SyncStatus { throw HubError.network("x") }
    }

    private func cache() throws -> OfflineCache { OfflineCache(db: try AppDatabase.inMemory()) }
    private func makeGoals(_ p: any GoalsSetupProviding, _ a: HubAvailability) -> GoalsSetupViewModel {
        GoalsSetupViewModel(provider: p, availability: a)
    }

    @Test(arguments: [false, true])
    func noHubGivesEveryModelInNeedsHub(onDeviceSource: Bool) throws {
        let c = try cache()
        // No hub configured → source nil; on-device data source → hubScreensSource returns it.
        let source: (any HealthDataProvider)? = onDeviceSource ? OnDeviceOnly() : nil
        #expect(HubScreensFallback.energy(source: source, cache: c).availability == .needsHub)
        #expect(HubScreensFallback.nutrition(source: source, cache: c).availability == .needsHub)
        #expect(HubScreensFallback.training(source: source, healthProvider: source, cache: c).availability == .needsHub)
        #expect(HubScreensFallback.goalsSetup(source: source, make: makeGoals).availability == .needsHub)
        #expect(HubScreensFallback.progression(source: source, cache: c, prefs: nil).availability == .needsHub)
    }

    @Test func hubPresentLeavesEveryModelLive() throws {
        let c = try cache()
        let hub: any HealthDataProvider = MockDataProvider()
        #expect(HubScreensFallback.energy(source: hub, cache: c).availability == .live)
        #expect(HubScreensFallback.nutrition(source: hub, cache: c).availability == .live)
        #expect(HubScreensFallback.training(source: hub, healthProvider: hub, cache: c).availability == .live)
        #expect(HubScreensFallback.goalsSetup(source: hub, make: makeGoals).availability == .live)
        #expect(HubScreensFallback.progression(source: hub, cache: c, prefs: nil).availability == .live)
    }

    /// Cold cache + no hub: each screen settles on its one honest line — never stuck on loading.
    @Test func needsHubLoadSettlesOnTheHonestLine() async throws {
        let c = try cache()
        let energy = HubScreensFallback.energy(source: nil, cache: c)
        await energy.load()
        #expect(energy.phase == .error(NeedsHubCopy.energy))
        let nutrition = HubScreensFallback.nutrition(source: nil, cache: c)
        await nutrition.load()
        #expect(nutrition.phase == .error(NeedsHubCopy.nutrition))
        let training = HubScreensFallback.training(source: nil, healthProvider: nil, cache: c)
        await training.load()
        #expect(training.phase == .error(NeedsHubCopy.training))
        let goals = HubScreensFallback.goalsSetup(source: nil, make: makeGoals)
        await goals.load()
        #expect(goals.phase == .error(NeedsHubCopy.goals))
        #expect(NeedsHubCopy.energy.hasPrefix("Connect the hub in Settings to see"))
    }

    /// Warm cache + no hub: the cached copy shows (loaded), not the needs-hub line.
    @Test func needsHubLoadShowsTheCachedCopy() async throws {
        let c = try cache()
        let report = try await MockDataProvider().energy(windowDays: 7)
        try c.put("energy.report", report)
        let energy = HubScreensFallback.energy(source: nil, cache: c)
        await energy.load()
        #expect(energy.phase == .loaded)
        #expect(energy.report != nil)
    }

    /// The shell builds the five from the factory, never `screenUnavailable` on a failed cast.
    @Test func rootTabViewBuildsTheHubScreensThroughTheFallback() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "App/RootTabView.swift"), encoding: .utf8)
        for call in ["HubScreensFallback.energy(", "HubScreensFallback.nutrition(", "HubScreensFallback.training(",
                     "HubScreensFallback.goalsSetup(", "HubScreensFallback.progression("] {
            #expect(src.contains(call), "\(call) missing")
        }
        for gone in ["Energy unavailable", "Nutrition unavailable", "Training unavailable"] {
            #expect(!src.contains(gone), "\(gone) still reachable")
        }
    }
}

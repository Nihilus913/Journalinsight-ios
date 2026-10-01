import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-FIX11 H2-06 (bug hunt 2026-10-01): Recovery offline showed "0 nights" and "Hub unreachable"
// although the hub's nights were cached. The on-device source (Developer › Read from Apple Watch)
// had answered [] and that empty answer replaced the hub's cache under the same key.

/// The on-device source: no hub capabilities, no nights yet.
nonisolated struct OnDeviceEmptyProvider: HealthDataProvider {
    let capabilities: DataCapability = [.recovery, .sleepSummary]
    func health() async throws -> HealthResponse { try await MockDataProvider().health() }
    func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("not on device") }
    func morning() async throws -> MorningResponse { throw HubError.network("not on device") }
    func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("not on device") }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { [] }
    func syncStatus() async throws -> SyncStatus { throw HubError.network("not on device") }
}

@Test @MainActor func hubOfflineRendersTheHubCacheAfterTheOnDeviceSource() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    await RecoveryViewModel(provider: RecoveryFlakyProvider(failing: false), cache: cache).load()   // hub nights cached
    let onDevice = RecoveryViewModel(provider: OnDeviceEmptyProvider(), cache: cache)
    await onDevice.load()
    #expect(onDevice.phase == .empty)
    #expect(onDevice.isOnDeviceSource)
    let offline = RecoveryViewModel(provider: RecoveryFlakyProvider(failing: true), cache: cache)
    await offline.load()
    #expect(offline.days.isEmpty == false)                // the cached hub nights, not "0 nights"
    #expect(offline.phase == .loaded)
    #expect(offline.hubReachable == false)                // with the staleness banner
}

// W-FIX11 H2-21: the on-device empty state never tells the user to sync the hub.
@Test func onDeviceEmptyCopyNamesTheWatch() {
    #expect(!recoveryEmptyText(onDevice: true).contains("hub"))
    #expect(recoveryEmptyText(onDevice: false) == "No data yet — run a sync on the hub.")
}

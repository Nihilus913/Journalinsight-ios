import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX-P2 RG-24 (B-52): Training with the hub down and nothing cached reads as the cold cache
/// ("No cached data yet …"), like every other tab — never the retired
/// "Hub unreachable — is the Mac awake and on the same network?".
@Suite struct RG24TrainingColdCacheCopyTests {
    private struct DeadHealth: HealthDataProvider {
        let capabilities: DataCapability = .hubAll
        private let inner = MockDataProvider()
        func health() async throws -> HealthResponse { try await inner.health() }
        func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("down") }
        func morning() async throws -> MorningResponse { throw HubError.network("down") }
        func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("down") }
        func recovery(windowDays: Int) async throws -> [RecoveryDay] { throw HubError.network("down") }
        func syncStatus() async throws -> SyncStatus { throw HubError.network("down") }
    }

    @Test @MainActor func coldCacheOfflineTrainingSaysNoCachedDataYet() async throws {
        let training = PlanWeekdayFakeProvider()
        training.readsFail = true
        let vm = TrainingViewModel(
            provider: training, healthProvider: DeadHealth(), cache: OfflineCache(db: try AppDatabase.inMemory()),
            strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "rg24.\(UUID().uuidString)")),
            outbox: nil, drainer: nil,
            now: { ISO8601DateFormatter().date(from: "2026-10-05T08:00:00Z")! }
        )
        await vm.load()
        #expect(vm.phase == .error(OfflineReadCopy.coldCache))
        #expect(vm.hubReachable == false)
    }

    @Test func noSourceCarriesTheRetiredCopy() throws {
        let root = B52NoDirectSendLintTests.root
        for rel in ["Packages/JIFeatures/Sources", "Packages/JIDesign/Sources", "App"] {
            let base = root.appending(path: rel)
            guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in e where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                #expect(!text.contains("is the Mac awake"), "\(url.lastPathComponent): retired hub-unreachable copy")
            }
        }
    }
}

import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

/// W-FIX-P2 RG-25 (B-52): the Why-today detail opened from a Decide "What drove it" row, offline
/// with a cold cache, still says which screen it is (a title) and shows the row's value the user
/// just tapped — never a title-less "No cached data yet" card alone.
@Suite struct RG25RationaleOfflineSeedTests {
    private struct DeadProvider: HealthDataProvider {
        let capabilities: DataCapability = .hubAll
        private let inner = MockDataProvider()
        func health() async throws -> HealthResponse { try await inner.health() }
        func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("down") }
        func morning() async throws -> MorningResponse { throw HubError.network("down") }
        func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("down") }
        func recovery(windowDays: Int) async throws -> [RecoveryDay] { throw HubError.network("down") }
        func syncStatus() async throws -> SyncStatus { try await inner.syncStatus() }
    }

    private let hrvRow = DecideSignalRowModel(id: "hrv", label: "HRV (7-day)", value: 22, unit: "ms", decimals: 0,
                                              status: .watch, detail: nil)

    @Test @MainActor func offlineDetailFromADecideRowHasATitleAndTheRowValue() async {
        let vm = GateRationaleViewModel(provider: DeadProvider())
        await vm.load()
        #expect(vm.phase == .error(OfflineReadCopy.coldCache))
        let face = try? #require(gateRationaleErrorFace(phase: vm.phase, seed: hrvRow))
        #expect(face?.title == "Why today")
        #expect(face?.row == hrvRow)
        #expect(face?.message == OfflineReadCopy.coldCache)
    }

    @Test func errorFaceWithoutASeedStillHasATitle() {
        let face = gateRationaleErrorFace(phase: .error("x"), seed: nil)
        #expect(face?.title == "Why today")
        #expect(face?.row == nil)
        #expect(gateRationaleErrorFace(phase: .loaded, seed: hrvRow) == nil)
    }
}

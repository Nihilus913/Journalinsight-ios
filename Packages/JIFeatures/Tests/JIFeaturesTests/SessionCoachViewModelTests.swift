import Foundation
import Testing
import JICore
@testable import JIFeatures

/// A `HealthDataProvider` double that deliberately does NOT conform to `LiveSessionProviding` —
/// stands in for `HubDataProvider` (which never conforms either, see `LiveSessionProviding.swift`)
/// without needing JIHub as a test dependency here.
private struct NotCapableProvider: HealthDataProvider {
    let capabilities: DataCapability = .hubAll
    func health() async throws -> HealthResponse { throw HubError.network("unused") }
    func gate(windowDays: Int) async throws -> GateResponse { throw HubError.network("unused") }
    func morning() async throws -> MorningResponse { throw HubError.network("unused") }
    func morningVerdict(date: String) async throws -> MorningVerdict { throw HubError.network("unused") }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { throw HubError.network("unused") }
    func syncStatus() async throws -> SyncStatus { throw HubError.network("unused") }
}

@Suite(.serialized)
struct SessionCoachViewModelTests {
    @Test @MainActor func noProviderIsNotCapable() {
        let vm = SessionCoachViewModel(provider: nil)
        #expect(!vm.capable)
        #expect(vm.sample == nil)
        #expect(vm.capState == .unknown)
    }

    @Test @MainActor func nonConformingProviderIsNotCapable() {
        let vm = SessionCoachViewModel(provider: NotCapableProvider())
        #expect(!vm.capable)
    }

    /// `start()` on a not-capable VM must never poll — asserted indirectly: `sample` stays `nil`
    /// even after waiting past a poll interval.
    @Test @MainActor func startOnNotCapableNeverPolls() async throws {
        let vm = SessionCoachViewModel(provider: NotCapableProvider(), pollIntervalMs: 20)
        vm.start()
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(vm.sample == nil)
    }

    @Test @MainActor func mockProviderPollsAndRendersSample() async throws {
        MockDataProvider.resetLiveSessionFeed()
        let vm = SessionCoachViewModel(provider: MockDataProvider(), pollIntervalMs: 20)
        #expect(vm.capable)
        vm.start()
        try await Task.sleep(nanoseconds: 60_000_000)
        vm.stop()
        #expect(vm.sample != nil)
        #expect(vm.sample?.hrBpm != nil)
        #expect(vm.elapsedText != "—")
    }

    /// Exit criterion: "polling stops on disappear" — `stop()` cancels the loop so no further
    /// ticks land after it returns.
    @Test @MainActor func stopHaltsFurtherTicks() async throws {
        MockDataProvider.resetLiveSessionFeed()
        let vm = SessionCoachViewModel(provider: MockDataProvider(), pollIntervalMs: 15)
        vm.start()
        try await Task.sleep(nanoseconds: 50_000_000)
        vm.stop()
        let frozen = vm.sample
        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(vm.sample == frozen)
    }

    @Test @MainActor func capStateBoundaries() {
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: nil) == .unknown)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 140) == .under)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 161) == .approaching)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 175) == .approaching)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 176) == .breach)
    }

    @Test @MainActor func toneMapsToReservedVerdictPalette() {
        #expect(SessionCoachViewModel.tone(for: .under) == .go)
        #expect(SessionCoachViewModel.tone(for: .approaching) == .amber)
        #expect(SessionCoachViewModel.tone(for: .breach) == .red)
        #expect(SessionCoachViewModel.tone(for: .unknown) == .muted)
    }

    /// CLAUDE.md rule 5 — every band, including "under", ships one concrete action, never a bare
    /// warning with nothing to do about it.
    @Test @MainActor func everyBandHasAConcreteAction() {
        for state: SessionCoachViewModel.CapState in [.unknown, .under, .approaching, .breach] {
            #expect(!SessionCoachViewModel.action(for: state).isEmpty)
        }
    }

    @Test func capCopyNeverClaimsTheUserChoseItYet() {
        #expect(sessionCoachCapTitle == "Your cap 175")
        #expect(sessionCoachCapCaption == "175 bpm is the cap in your gate settings. The app never raises it.")
        #expect(!sessionCoachCapCaption.contains("You chose"))   // user-set cap is W4
    }
}

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
        // Toby's migrated limit (cap 175): the pre-W4 boundaries hold.
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: nil, limitBpm: 175) == .unknown)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 140, limitBpm: 175) == .under)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 161, limitBpm: 175) == .approaching)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 175, limitBpm: 175) == .approaching)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 176, limitBpm: 175) == .breach)
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
        for state: SessionCoachViewModel.CapState in [.unknown, .under, .approaching, .breach, .noLimit] {
            #expect(!SessionCoachViewModel.action(for: state, settings: .legacyPreW4).isEmpty)
        }
    }

    // MARK: - B-57 W4: the user's optional cap and zones

    private let toby = GateSettings.legacyPreW4                                  // cap 175, avoid Zone 5 (176–198)
    private let zone5Trainer = GateSettings(hrCapBpm: nil, zones: .derived(anchor: .maxHr, bpm: 190),
                                            hrCapConfirmedOn: "2026-09-24")       // answered "No", trains Zone 5

    @Test func limitIsTheCapAndOrTheTopOfZone4() {
        #expect(SessionCoachViewModel.limitBpm(toby) == 175)
        #expect(SessionCoachViewModel.limitBpm(GateSettings(hrCapBpm: 190, avoidZone5: true, zones: .legacyPreW4)) == 175)
        #expect(SessionCoachViewModel.limitBpm(GateSettings(hrCapBpm: 168)) == 168)
        #expect(SessionCoachViewModel.limitBpm(zone5Trainer) == nil)
        #expect(SessionCoachViewModel.limitBpm(GateSettings()) == nil)
    }

    @Test @MainActor func capStateFollowsTheUsersLimit() {
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: nil, limitBpm: 168) == .unknown)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 150, limitBpm: 168) == .under)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 153, limitBpm: 168) == .approaching)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 169, limitBpm: 168) == .breach)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 176, limitBpm: 175) == .breach)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 175, limitBpm: 175) == .approaching)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: 185, limitBpm: nil) == .noLimit)
        #expect(SessionCoachViewModel.deriveCapState(hrBpm: nil, limitBpm: nil) == .unknown)
        #expect(SessionCoachViewModel.action(for: .breach, settings: GateSettings(hrCapBpm: 168)) == "Over your 168 limit — back off now.")
        #expect(SessionCoachViewModel.action(for: .breach, settings: toby)
                == "Over your 175 limit — back off now. You chose to stay out of Zone 5 (176–198).")
        #expect(SessionCoachViewModel.tone(for: .noLimit) == .muted)
    }

    @Test @MainActor func modelCarriesTheSettings() {
        let vm = SessionCoachViewModel(provider: nil, settings: GateSettings(hrCapBpm: 182, hrCapConfirmedOn: "2026-09-24"))
        #expect(vm.hrCapBpm == 182 && vm.limitBpm == 182)
        #expect(SessionCoachViewModel(provider: nil).hrCapBpm == nil)          // no app default
        #expect(SessionCoachViewModel(provider: nil).limitBpm == nil)
    }

    @Test func capCopyTellsTheTruthAboutWhoChoseIt() {
        #expect(sessionCoachCapTitle(GateSettings(hrCapBpm: 175)) == "Your cap 175")
        #expect(sessionCoachCapCaption(GateSettings(hrCapBpm: 175, hrCapConfirmedOn: "2026-09-24")) == "You chose 175 in setup. The app never raises it.")
        #expect(sessionCoachCapCaption(toby) == "175 bpm is from your earlier setup. Confirm or change it in Gate thresholds. The app never raises it.")
    }

    /// Review Focus 6: no cap ⇒ no cap text anywhere in SessionCoach.
    @Test func noCapMeansNoCapCopy() {
        #expect(sessionCoachCapTitle(zone5Trainer) == nil)
        #expect(sessionCoachCapCaption(zone5Trainer) == nil)
        #expect(sessionCoachSafetyLine(zone5Trainer) == nil)
        #expect(sessionCoachUnitLine(zone5Trainer) == "bpm")
        #expect(!sessionCoachIntro(zone5Trainer).contains("limit"))
        #expect(sessionCoachSafetyLine(toby) == "Your limits still apply either way: HR ≤ 175 · Zone 5 (176–198) avoided.")
        #expect(sessionCoachUnitLine(toby) == "bpm · cap 175 · Z5 176–198 avoided")
    }
}

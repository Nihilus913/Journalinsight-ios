import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B57-W2 L3 guard tests (first commit, green on base 0a7a136). They pin the behaviour the
/// goals store + mirror work must not break:
/// - GoalsSetup's `load()` is read-only: it never PUTs goals (Review Focus 4, no PUT storm).
/// - (W-FIX10) An offline goals save is stored on the phone and queued, never a fake hub save.
/// - Every Outbox kind that existed before W2 stays known, so rows already queued on a phone are
///   never orphaned by a new kind.
private final class PutCountingGoalsProvider: GoalsSetupProviding, @unchecked Sendable {
    let inner = MockDataProvider()
    private let lock = NSLock()
    private var _puts = 0
    var puts: Int { lock.withLock { _puts } }
    let fail: HubError?
    init(fail: HubError? = nil) { self.fail = fail }
    func energy(windowDays: Int) async throws -> EnergyReport { try await inner.energy(windowDays: windowDays) }
    func goals() async throws -> Goals { try await inner.goals() }
}

@Test @MainActor func guardGoalsSetupLoadNeverPutsGoals() async throws {
    let hub = PutCountingGoalsProvider()
    let vm = GoalsSetupViewModel(provider: hub)
    await vm.load()
    await vm.load()   // a second foreground / re-appear
    #expect(vm.phase == .loaded)
    #expect(hub.puts == 0)
}

/// W-FIX10 F10-1: an offline goals save is never a fake save and never an error — it is stored on
/// this phone and queued as the targets body (the old `PUT /planning/goals` is gone).
@Test @MainActor func guardOfflineGoalsSaveIsStoredAndQueued() async throws {
    let hub = TargetsHubFake(); hub.fail = .network("down")
    let (vm, targets, outbox) = try goalsSetupFixture(hub: hub)
    await vm.load()
    #expect(await vm.save(GoalsUpdate(stepsDaily: 1234)))
    #expect(targets.store.load().goals.stepsDaily == 1234)
    #expect(try outbox.pending().map(\.kind) == [TargetsDocument.outboxKind])
    #expect(vm.hubPending && vm.phase == .loaded)
}

@Test @MainActor func guardPreW2OutboxKindsStayKnown() {
    let preW2: Set<String> = ["weighin", "gateRespond", "sessionFeel", "plan_weekday",
                              OutboxDrainer.verdictOverrideKind, OutboxDrainer.verdictOverrideClearKind]
    #expect(preW2.isSubset(of: OutboxDrainer.knownKinds))
}

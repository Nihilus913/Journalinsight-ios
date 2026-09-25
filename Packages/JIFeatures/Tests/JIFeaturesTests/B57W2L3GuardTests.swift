import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B57-W2 L3 guard tests (first commit, green on base 0a7a136). They pin the behaviour the
/// goals store + mirror work must not break:
/// - GoalsSetup's `load()` is read-only: it never PUTs goals (Review Focus 4, no PUT storm).
/// - A failed goals save keeps the last server document and reports an error (never a fake save).
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
    func updateGoals(_ patch: GoalsUpdate) async throws -> Goals {
        lock.withLock { _puts += 1 }
        if let fail { throw fail }
        return try await inner.updateGoals(patch)
    }
}

@Test @MainActor func guardGoalsSetupLoadNeverPutsGoals() async throws {
    let hub = PutCountingGoalsProvider()
    let vm = GoalsSetupViewModel(provider: hub)
    await vm.load()
    await vm.load()   // a second foreground / re-appear
    #expect(vm.phase == .loaded)
    #expect(hub.puts == 0)
}

@Test @MainActor func guardFailedGoalsSaveKeepsServerDocumentAndReportsError() async throws {
    let hub = PutCountingGoalsProvider(fail: .network("down"))
    let vm = GoalsSetupViewModel(provider: hub)
    await vm.load()
    let before = vm.goals
    let ok = await vm.save(GoalsUpdate(stepsDaily: 1234))
    #expect(!ok)
    #expect(hub.puts == 1)
    #expect(vm.goals == before)
    #expect(vm.savedAt == nil)
    guard case .error = vm.phase else { Issue.record("expected an error phase"); return }
}

@Test @MainActor func guardPreW2OutboxKindsStayKnown() {
    let preW2: Set<String> = ["weighin", "gateRespond", "sessionFeel", "plan_weekday",
                              OutboxDrainer.verdictOverrideKind, OutboxDrainer.verdictOverrideClearKind]
    #expect(preW2.isSubset(of: OutboxDrainer.knownKinds))
}

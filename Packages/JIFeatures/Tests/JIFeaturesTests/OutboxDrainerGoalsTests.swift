import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

@MainActor final class GoalsRecorder: GoalsProviding, @unchecked Sendable { // test-only, MainActor-confined
    var patches: [GoalsUpdate] = []
    var fail: HubError?
    nonisolated func updateGoals(_ patch: GoalsUpdate) async throws -> Goals {
        try await MainActor.run {
            if let fail { throw fail }
            patches.append(patch)
            return Goals(weight: WeightGoal(targetKg: 75), strength: [], nutrition: NutritionGoal(
                kcalGoal: patch.nutrition?.kcalGoal, proteinG: patch.nutrition?.proteinG,
                carbsG: patch.nutrition?.carbsG, fatG: patch.nutrition?.fatG))
        }
    }
}

@Test @MainActor func drainOnceDeliversAQueuedGoalsPut() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = GoalsRecorder()
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, goals: hub)
    let patch = GoalsUpdate(nutrition: .init(kcalGoal: 1800, proteinG: 155, carbsG: 144, fatG: 49))
    let id = try outbox.enqueue(kind: OutboxDrainer.goalsKind, payload: patch)

    let results = await drainer.drainOnce()

    guard case .success(.goals(let g)) = results[id] else { Issue.record("expected goals success"); return }
    #expect(hub.patches == [patch])
    #expect(g.nutrition.kcalGoal == 1800)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func failedGoalsPutStaysQueuedWithTheReason() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = GoalsRecorder(); hub.fail = .network("down")
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, goals: hub)
    _ = try outbox.enqueue(kind: OutboxDrainer.goalsKind, payload: GoalsUpdate(nutrition: .init(proteinG: 160)))
    _ = await drainer.drainOnce()
    let row = try #require(try outbox.pending().first)
    #expect(row.attempts == 1)
    #expect(row.lastError == "down")
}

@Test @MainActor func goalsKindIsKnownAndDrainableOnlyWithAProvider() {
    #expect(OutboxDrainer.knownKinds.contains(OutboxDrainer.goalsKind))
    let outbox = try! Outbox(db: AppDatabase.inMemory())
    #expect(!OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil).drainableKinds.contains(OutboxDrainer.goalsKind))
}

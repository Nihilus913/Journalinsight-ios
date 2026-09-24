import Foundation
import SwiftUI
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W5b-L4 (P-local-mirrors) — card exit: "LocalMirrors renders all four sections from fixtures,
/// DecisionLog shows real rows after a respond". The first two domains come from the synced
/// hub-contract fixtures via `MockDataProvider` (`planning_goals`, `planning_kpi_targets`);
/// the third is a real `decision_log_mirror` row written by
/// `GateRespondViewModel.respond`.

@MainActor
private func fixtureModel(db: AppDatabase) async throws -> LocalMirrorsViewModel {
    let mock = MockDataProvider()
    let goals = try await mock.goals()
    let targets = try await mock.kpiTargets()
    return LocalMirrorsViewModel(
        goals: goals, goalStore: GoalStore(db: db), targets: targets,
        decisionLog: DecisionLogStore(db: db)
    )
}

@Test @MainActor func loadFillsAllFourSectionsFromFixtures() async throws {
    let db = try AppDatabase.inMemory()
    let model = try await fixtureModel(db: db)

    await model.load()

    #expect(model.goals != nil)
    #expect(!model.targets.isEmpty)
    #expect(model.decisions == []) // loaded (not nil) — nothing answered yet
}

@Test @MainActor func decisionLogShowsTheRowARespondWrote() async throws {
    let db = try AppDatabase.inMemory()
    let respond = GateRespondViewModel(
        recommendation: .progress, provider: MockDataProvider(),
        outbox: Outbox(db: db), decisionLog: DecisionLogStore(db: db)
    )
    await respond.respond(choice: .yes)

    let model = try await fixtureModel(db: db)
    await model.load()

    #expect(model.decisions?.count == 1)
    #expect(model.decisions?[0].userChoice == "y")
    #expect(model.decisions?[0].recommendation == "PROGRESS")
    #expect(model.decisions?[0].synced == true)
}

/// The local-first fallback: no hub document in hand (`goals: nil`) → `goal_targets_mirror`.
@Test @MainActor func loadFallsBackToTheGoalTargetsMirrorWhenNoHubDocumentIsInHand() async throws {
    let db = try AppDatabase.inMemory()
    let store = GoalStore(db: db)
    try store.saveGoalTargetsMirror(try await MockDataProvider().goals())
    let model = LocalMirrorsViewModel(goals: nil, goalStore: store, targets: [], decisionLog: DecisionLogStore(db: db))

    await model.load()

    #expect(model.goals != nil)
}

@Test @MainActor func loadWithoutADatabaseStillSettlesToEmptyNotNil() async {
    let model = LocalMirrorsViewModel(decisionLog: nil)
    await model.load()
    #expect(model.decisions == [])
    #expect(model.goals == nil)
}

@Test @MainActor func viewsConstruct() async throws {
    let db = try AppDatabase.inMemory()
    let model = try await fixtureModel(db: db)
    _ = LocalMirrorsView(model: model).body
    _ = DecisionLogSection(entries: nil).body
    _ = DecisionLogSection(entries: []).body
    _ = DecisionLogSection(entries: [DecisionLogEntry(id: 1, remoteLogId: nil, loggedAt: "2026-09-18T07:00:00Z", windowDays: 7, recommendation: "PROGRESS", userChoice: "y", overrideReason: nil, synced: false)]).body
    _ = LocalMirrorsSection().body
    #expect(SettingsRegistry.sections.contains { $0.id == LocalMirrorsSection.sectionId })
    #expect(SettingsGroup(sortKey: LocalMirrorsSection().sortKey) == .data)
}

@Test @MainActor func gateRespondCardConstructsForEveryRecommendation() throws {
    let db = try AppDatabase.inMemory()
    for recommendation in [GateRecommendation.progress, .maintain, .reduce, .insufficientData] {
        let model = GateRespondViewModel(recommendation: recommendation, provider: MockDataProvider(), outbox: Outbox(db: db), decisionLog: DecisionLogStore(db: db))
        _ = GateRespondCard(model: model).body
        _ = VerdictHeroView(verdict: verdictParts("GO — Upper"), readiness: 72, readinessMissing: false, gateRespondModel: model).body
    }
}

/// B-57 W1 T28: Local mirrors keeps goals, KPI targets and decisions only.
@Test @MainActor func localMirrorsHasNoChallengesSection() throws {
    let db = try AppDatabase.inMemory()
    let model = LocalMirrorsViewModel(goalStore: GoalStore(db: db), decisionLog: DecisionLogStore(db: db))
    #expect(Mirror(reflecting: model).children.allSatisfy { $0.label != "challengesModel" })
}

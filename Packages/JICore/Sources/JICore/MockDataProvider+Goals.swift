import Foundation

/// W4-L3 — `MockDataProvider`'s `GoalsProviding` conformance. No mock hub to PUT against, so this
/// applies the patch locally via `mergeGoals` against the synced `planning_goals` fixture —
/// mirrors `MockDataProvider+Training.swift`'s no-op-write convention, but a real merge (not just
/// an echo) since `GoalsSetupViewModel` reads the returned document back into its form.
extension MockDataProvider: GoalsProviding {
    public func updateGoals(_ patch: GoalsUpdate) async throws -> Goals {
        let current = try Self.loadGoalsFixture()
        return mergeGoals(current: current, patch: patch)
    }

    private static func loadGoalsFixture() throws -> Goals {
        guard let url = MockDataProvider.fixtureURL(named: "planning_goals")
        else { throw HubError.decoding("missing fixture planning_goals") }
        return try JSON.decoder.decode(Goals.self, from: Data(contentsOf: url))
    }
}

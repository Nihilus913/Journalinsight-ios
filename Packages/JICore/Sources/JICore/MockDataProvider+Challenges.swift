import Foundation

/// Previews + tests only, same contract as `MockDataProvider+Training.swift` (frozen file — this
/// conformance lives here instead, per the Data seam). Serves the synced hub-contract fixture for
/// reads; every write resolves immediately as a successful no-op (no mock hub to mutate against),
/// same convention as `MockDataProvider+Training.swift`'s `updateExercise`.
extension MockDataProvider: ChallengesProviding {
    public func challenges() async throws -> [GateChallenge] {
        try Self.loadChallengesFixture("planning_challenges", as: ChallengesResponse.self).challenges
    }

    public func createChallenge(_ input: ChallengeCreateInput) async throws -> GateChallenge {
        GateChallenge(
            challengeId: -1, title: input.title, hypothesis: input.hypothesis, startDate: input.startDate,
            targetSessions: input.targetSessions, sessionFilter: input.sessionFilter, status: .active,
            createdAt: nil, completedAt: nil, resultNote: nil, updatedAt: nil,
            progress: ChallengeProgress(count: 0, target: input.targetSessions, executionScore: 0, pace: nil, wantsCompletePrompt: false)
        )
    }

    public func updateChallenge(challengeId: Int, patch: ChallengeUpdatePatch) async throws -> GateChallenge {
        var row = try await existingOrPlaceholder(challengeId)
        if let title = patch.title { row.title = title }
        if let hypothesis = patch.hypothesis { row.hypothesis = hypothesis }
        if let targetSessions = patch.targetSessions { row.targetSessions = targetSessions }
        if let startDate = patch.startDate { row.startDate = startDate }
        if let sessionFilter = patch.sessionFilter { row.sessionFilter = sessionFilter }
        if let resultNote = patch.resultNote { row.resultNote = resultNote }
        return row
    }

    public func archiveChallenge(challengeId: Int, status: ChallengeArchiveStatus, resultNote: String?) async throws -> GateChallenge {
        var row = try await existingOrPlaceholder(challengeId)
        row.status = status == .completed ? .completed : .archived
        if let resultNote { row.resultNote = resultNote }
        return row
    }

    public func deleteChallenge(challengeId: Int) async throws {}

    private func existingOrPlaceholder(_ challengeId: Int) async throws -> GateChallenge {
        if let hit = try? await challenges().first(where: { $0.challengeId == challengeId }) { return hit }
        return GateChallenge(
            challengeId: challengeId, title: "", hypothesis: "", startDate: "", targetSessions: 1,
            sessionFilter: "interval", status: .active, createdAt: nil, completedAt: nil, resultNote: nil,
            updatedAt: nil, progress: ChallengeProgress(count: 0, target: 1, executionScore: 0, pace: nil, wantsCompletePrompt: false)
        )
    }

    private static func loadChallengesFixture<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        guard let url = MockDataProvider.fixtureURL(named: name) else {
            throw HubError.decoding("missing fixture \(name)")
        }
        return try JSON.decoder.decode(T.self, from: Data(contentsOf: url))
    }
}

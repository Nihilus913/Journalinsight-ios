import Foundation
import JICore

/// `HubDataProvider.client` is internal (L0, W3b, B-14) — this conformance uses it directly, same
/// convention as `HubDataProvider+Training.swift`. Endpoints from `app/planning/router.py`'s
/// challenges surface (GET/POST/PATCH/DELETE `/api/v1/planning/challenges[/{id}[/archive]]`).
extension HubDataProvider: ChallengesProviding {
    public func challenges() async throws -> [GateChallenge] {
        let response: ChallengesResponse = try await client.get("/api/v1/planning/challenges")
        return response.challenges
    }

    public func createChallenge(_ input: ChallengeCreateInput) async throws -> GateChallenge {
        try await client.send("POST", "/api/v1/planning/challenges", body: input)
    }

    public func updateChallenge(challengeId: Int, patch: ChallengeUpdatePatch) async throws -> GateChallenge {
        try await client.send("PATCH", "/api/v1/planning/challenges/\(challengeId)", body: patch)
    }

    public func archiveChallenge(challengeId: Int, status: ChallengeArchiveStatus, resultNote: String?) async throws -> GateChallenge {
        let body = ChallengeArchiveBody(status: status, resultNote: resultNote)
        return try await client.send("POST", "/api/v1/planning/challenges/\(challengeId)/archive", body: body)
    }

    public func deleteChallenge(challengeId: Int) async throws {
        try await client.delete("/api/v1/planning/challenges/\(challengeId)")
    }
}

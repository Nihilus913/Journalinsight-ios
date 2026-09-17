/// Challenges screen's own hub slice (W3b-L3), added alongside the frozen `HealthDataProvider`
/// the same way W3a's `TrainingProviding` was (Data seam: several screen lanes land in parallel
/// this wave — a shared protocol file would collide). `HubDataProvider`/`MockDataProvider` conform
/// via their own `+Challenges` extension files.
public protocol ChallengesProviding: Sendable {
    /// `GET /api/v1/planning/challenges` — every challenge regardless of status.
    func challenges() async throws -> [GateChallenge]

    /// `POST /api/v1/planning/challenges` — active by default; does not archive any existing
    /// active challenge.
    func createChallenge(_ input: ChallengeCreateInput) async throws -> GateChallenge

    /// `PATCH /api/v1/planning/challenges/{challengeId}` — partial update.
    func updateChallenge(challengeId: Int, patch: ChallengeUpdatePatch) async throws -> GateChallenge

    /// `POST /api/v1/planning/challenges/{challengeId}/archive` — retires the challenge
    /// (`.completed` or `.archived`), stamping `completed_at`. `resultNote` when non-nil is sent
    /// alongside the retirement; `nil` leaves any existing note untouched.
    func archiveChallenge(challengeId: Int, status: ChallengeArchiveStatus, resultNote: String?) async throws -> GateChallenge

    /// `DELETE /api/v1/planning/challenges/{challengeId}` — hard delete, only permitted (server-
    /// side, 409 otherwise) when the challenge has zero recorded sessions and was never completed.
    func deleteChallenge(challengeId: Int) async throws
}

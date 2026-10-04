import JICore

/// W-B91 — `HubDataProvider`'s `TrainingBreakProviding` conformance (`GET/PUT
/// /api/v1/planning/training-break`). `TrainingBreak`'s keys are already the wire spelling.
extension HubDataProvider: TrainingBreakProviding {
    public func trainingBreak() async throws -> TrainingBreak {
        try await client.get("/api/v1/planning/training-break")
    }

    public func setTrainingBreak(paused: Bool, since: String? = nil) async throws -> TrainingBreak {
        try await client.send("PUT", "/api/v1/planning/training-break", body: TrainingBreak(paused: paused, since: since))
    }
}

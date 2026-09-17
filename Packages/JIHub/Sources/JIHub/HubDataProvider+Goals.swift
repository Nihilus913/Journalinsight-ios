import JICore

/// W4-L3 — `HubDataProvider`'s `GoalsProviding` conformance.
extension HubDataProvider: GoalsProviding {
    public func updateGoals(_ patch: GoalsUpdate) async throws -> Goals {
        try await client.send("PUT", "/api/v1/planning/goals", body: patch)
    }
}

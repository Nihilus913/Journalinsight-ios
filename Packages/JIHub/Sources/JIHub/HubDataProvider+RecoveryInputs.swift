import JICore

/// B-57 W3 — `HubDataProvider`'s `RecoveryInputsProviding` conformance. The route validates
/// `window_days` in 1…365, so the client clamps rather than earning a 422.
extension HubDataProvider: RecoveryInputsProviding {
    public func recoveryInputs(date: String, windowDays: Int = 42) async throws -> [RecoveryInputDay] {
        let r: RecoveryInputsReport = try await client.get(
            "/api/v1/vitals/recovery-inputs",
            query: ["date": date, "window_days": String(min(max(windowDays, 1), 365))]
        )
        return r.days
    }
}

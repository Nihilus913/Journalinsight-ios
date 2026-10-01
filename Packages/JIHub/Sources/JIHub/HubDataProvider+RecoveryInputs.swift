import JICore

/// B-57 W3 — `HubDataProvider`'s `RecoveryInputsProviding` conformance. The route validates
/// `window_days` in 1…365, so the client clamps rather than earning a 422.
extension HubDataProvider: RecoveryInputsProviding {
    public func recoveryInputs(date: String, windowDays: Int = 42) async throws -> [RecoveryInputDay] {
        try await recoveryInputsReport(date: date, windowDays: windowDays).days
    }

    /// W-FIX10 R-04: the envelope with the hub's DH-4 `calibration` block (nil from an older hub).
    public func recoveryInputsReport(date: String, windowDays: Int = 42) async throws -> RecoveryInputsReport {
        try await client.get(
            "/api/v1/vitals/recovery-inputs",
            query: ["date": date, "window_days": String(min(max(windowDays, 1), 365))]
        )
    }
}

import JICore

/// W-B57b (B-62) — `HubDataProvider`'s `VerdictOverrideProviding` conformance, on the same
/// `client.send` / `client.delete` write seam as `HubDataProvider+GateRespond.swift`.
/// `VerdictOverrideBody`'s keys are already the wire spelling, so `send`'s plain `JSONEncoder()`
/// emits exactly `{"date","choice","reason"}`.
extension HubDataProvider: VerdictOverrideProviding {
    public func setVerdictOverride(date: String, choice: VerdictOverrideChoice, reason: String = "") async throws -> VerdictOverride {
        try await client.send("POST", "/api/v1/planning/verdict-override",
                              body: VerdictOverrideBody(date: date, choice: choice, reason: reason))
    }

    public func clearVerdictOverride(date: String) async throws {
        try await client.delete("/api/v1/planning/verdict-override", query: ["date": date])
    }
}

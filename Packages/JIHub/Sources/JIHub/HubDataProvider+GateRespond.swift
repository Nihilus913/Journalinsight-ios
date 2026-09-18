import JICore

/// W5b-L4 — `HubDataProvider`'s `GateRespondProviding` conformance. Uses `client.send` (the W3b-L0
/// write seam) for both POSTs, same as every other W3+/W5 write lane; `HubDataProvider.swift`
/// itself stays frozen.
///
/// Both bodies spell their own snake_case `CodingKeys` (`DTOs/GateRespond.swift`) because
/// `send` encodes with a plain `JSONEncoder()` — see its doc comment.
extension HubDataProvider: GateRespondProviding {
    public func respondGate(choice: GateChoice, overrideReason: String = "", windowDays: Int = 7) async throws -> GateRespondResult {
        let body = GateRespondBody(choice: choice, overrideReason: overrideReason, windowDays: windowDays)
        return try await client.send("POST", "/api/v1/planning/gate/respond", body: body)
    }

    public func logFeel(feelScore: Int, notes: String = "", date: String? = nil) async throws -> FeelResult {
        let body = FeelBody(feelScore: feelScore, notes: notes, date: date)
        return try await client.send("POST", "/api/v1/planning/feel", body: body)
    }
}

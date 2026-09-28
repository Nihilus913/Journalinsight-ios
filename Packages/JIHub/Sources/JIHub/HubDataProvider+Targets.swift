import JICore

/// W-TGT — `TargetsProviding`: the ONE mirror body (`GET/PUT /api/v1/planning/targets`, spec §3).
/// `HubClient.send` encodes with a plain `JSONEncoder()`, so the body is the document already
/// snake-cased by `JSON.encoder` (`TargetsDocument.wireBody()`); the answer decodes with
/// `JSON.decoder` like every other hub response.
///
/// W-FIX8 T-1 (P0 2026-09-28 14:51: a first-launch phone PUT an EMPTY document and wiped Toby's
/// goals): this is the one place every targets write goes through (the outbox drainer, the Limits
/// mirror), so the guard lives here. A goals-empty body without `clearAllGoals` first reads the
/// hub; if the hub holds goals, NOTHING is sent and `TargetsWouldClearGoals(server:)` is thrown for
/// the phone to adopt. The hub's own 409 (same rule, server side) maps to the same error.
extension HubDataProvider: TargetsProviding {
    public func targets() async throws -> TargetsDocument {
        try await client.get("/api/v1/planning/targets")
    }

    public func putTargets(_ document: TargetsDocument) async throws -> TargetsDocument {
        if document.goals.isEmpty && !document.clearAllGoals {
            let server = try await targets()
            if !server.goals.isEmpty { throw TargetsWouldClearGoals(server: server) }
        }
        let body: JSONValue
        do { body = try document.wireBody() } catch { throw HubError.decoding("/api/v1/planning/targets: encode \(error)") }
        do {
            return try await client.send("PUT", "/api/v1/planning/targets", body: body)
        } catch HubError.duplicate, HubError.http(status: 409, detail: _) {   // 409 decodes as `.duplicate`
            throw TargetsWouldClearGoals(server: try await targets())
        }
    }
}

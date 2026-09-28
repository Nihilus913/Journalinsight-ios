import JICore

/// W-TGT — `TargetsProviding`: the ONE mirror body (`GET/PUT /api/v1/planning/targets`, spec §3).
/// `HubClient.send` encodes with a plain `JSONEncoder()`, so the body is the document already
/// snake-cased by `JSON.encoder` (`TargetsDocument.wireBody()`); the answer decodes with
/// `JSON.decoder` like every other hub response.
extension HubDataProvider: TargetsProviding {
    public func targets() async throws -> TargetsDocument {
        try await client.get("/api/v1/planning/targets")
    }

    public func putTargets(_ document: TargetsDocument) async throws -> TargetsDocument {
        let body: JSONValue
        do { body = try document.wireBody() } catch { throw HubError.decoding("/api/v1/planning/targets: encode \(error)") }
        return try await client.send("PUT", "/api/v1/planning/targets", body: body)
    }
}

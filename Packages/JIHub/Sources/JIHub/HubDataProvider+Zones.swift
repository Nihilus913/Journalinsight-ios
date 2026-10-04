import JICore

/// B-95 (BP-26) — `HubDataProvider`'s `ZoneTimeProviding` conformance (time in zone over a range).
extension HubDataProvider: ZoneTimeProviding {
    public func trainingZones(from: String, to: String, bucket: String, scope: String) async throws -> ZoneTimeRange {
        try await client.get("/api/v1/training/zones",
                             query: ["from": from, "to": to, "bucket": bucket, "scope": scope])
    }
}

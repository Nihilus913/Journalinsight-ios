import JICore

/// B-94 b94p3 (BP-4) — `HubDataProvider`'s `CardioSeriesProviding` conformance (runs + VO2 max).
extension HubDataProvider: CardioSeriesProviding {
    public func cardioSeries(range: String) async throws -> CardioSeries {
        try await client.get("/api/v1/training/cardio-series", query: ["range": range])
    }
}

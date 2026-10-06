import JICore

/// W-B98A B98-4 (B-98 5a) — `HubDataProvider`'s `ActivitySeriesProviding` conformance
/// (Activity detail: km splits + HR/pace chart).
extension HubDataProvider: ActivitySeriesProviding {
    public func activitySeries(activityId: Int) async throws -> ActivitySeries {
        try await client.get("/api/v1/training/activity/\(activityId)/series")
    }
}

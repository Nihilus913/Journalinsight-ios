import JICore

/// W-B92 C-3 — `HubDataProvider`'s `TrainingCalendarProviding` conformance. An older hub answers
/// 404: that is `TrainingCalendarUnavailable`, so the month is built on the phone instead of
/// showing an error (B-52 offline-first).
extension HubDataProvider: TrainingCalendarProviding {
    public func trainingCalendar(month: String) async throws -> TrainingCalendarMonth {
        do {
            return try await client.get("/api/v1/training/calendar", query: ["month": month])
        } catch HubError.http(status: 404, _) {
            throw TrainingCalendarUnavailable()
        }
    }
}

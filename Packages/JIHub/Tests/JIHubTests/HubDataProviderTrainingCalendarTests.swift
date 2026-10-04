import Foundation
import Testing
import JICore
@testable import JIHub

/// W-B92 C-3 — `HubDataProvider+TrainingCalendar.swift`: `GET /api/v1/training/calendar?month=`
/// decodes; an old hub's 404 is `TrainingCalendarUnavailable`. Serial `HubClientTests` extension.
extension HubClientTests {
    private func calendarProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8281")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func trainingCalendarSendsTheMonthAndDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/training/calendar"] = (200, Data("""
        {"month": "2026-09", "today": "2026-10-04", "synced_through": "2026-09-29",
         "days": [{"date": "2026-09-21", "planned": {"name": "Day 1 Full Upper + Z2 40min", "type": "strength",
                   "session_type": "strength", "prescription": "Day 1 Full Upper + Z2 40min", "source": "snapshot", "template_id": null},
                   "state": "done", "status": "done", "credited": true,
                   "activities": [{"activity_id": 7, "type": "running", "duration_sec": 3420, "z2_share": 0.62}]}],
         "summary": {"done": 3, "partial": 3, "missed": 19, "unknown": 1, "planned": 0, "rest": 4, "owed_to_date": 26}}
        """.utf8))
        let m = try await calendarProvider().trainingCalendar(month: "2026-09")
        #expect(m.days.first?.state == .done && m.days.first?.activities.first?.z2Share == 0.62)
        #expect(m.summary.owedToDate == 26 && m.syncedThrough == "2026-09-29")
        let url = try #require(StubURLProtocol.lastRequest?.url)
        #expect(url.path == "/api/v1/training/calendar" && url.query?.contains("month=2026-09") == true)
    }

    @Test func trainingCalendarOldHub404IsUnavailable() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/training/calendar"] = (404, Data("{\"detail\":\"Not Found\"}".utf8))
        await #expect(throws: TrainingCalendarUnavailable.self) { _ = try await self.calendarProvider().trainingCalendar(month: "2026-09") }
    }
}

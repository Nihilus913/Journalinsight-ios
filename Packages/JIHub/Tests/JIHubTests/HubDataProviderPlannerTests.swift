import Foundation
import Testing
import JICore
@testable import JIHub

/// W-PLANNER PL-3 — `HubDataProvider+Planner.swift`: `GET /api/v1/planning/workouts` decodes the
/// PL-1 rows; an old hub's 404 is `PlannerWorkoutsUnavailable` (the phone falls back), any other
/// failure stays a named `HubError`. Serial `HubClientTests` extension (StubURLProtocol is global).
extension HubClientTests {
    private func plannerProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8281")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func plannerWorkoutsGetsTheRouteAndDecodesBothKinds() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/workouts"] = (200, Data("""
        [{"ref": "s4", "kind": "plan_session", "name": "Day 4 Full Upper", "sport": "strength", "weekdays": [], "lift_count": 6, "summary": "6 lifts", "garmin": null, "editable": false},
         {"ref": "t2", "kind": "template", "name": "Zone 2 40 min", "sport": "running", "weekdays": [0], "lift_count": 0, "summary": "40 min", "garmin": null, "editable": true}]
        """.utf8))
        let rows = try await plannerProvider().plannerWorkouts()
        #expect(rows.map(\.ref) == ["s4", "t2"])
        #expect(rows[0].sessionId == 4 && rows[0].weekdays.isEmpty && rows[0].liftCount == 6)
        #expect(rows[1].templateId == 2 && rows[1].weekdays == [0])
        #expect(StubURLProtocol.lastRequest?.httpMethod == "GET")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func plannerWorkoutsOldHub404IsUnavailable() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/workouts"] = (404, Data("{\"detail\":\"Not Found\"}".utf8))
        await #expect(throws: PlannerWorkoutsUnavailable.self) { _ = try await self.plannerProvider().plannerWorkouts() }
    }

    @Test func plannerWorkouts401StaysUnauthorized() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/workouts"] = (401, Data("{\"detail\":\"unauthorized\"}".utf8))
        await #expect(throws: HubError.unauthorized) { _ = try await self.plannerProvider().plannerWorkouts() }
    }
}

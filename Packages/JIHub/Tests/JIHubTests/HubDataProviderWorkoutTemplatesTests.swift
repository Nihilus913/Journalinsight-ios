import Foundation
import Testing
import JICore
@testable import JIHub

/// B-37-L1 — exercises `HubDataProvider`'s `WorkoutTemplatesProviding` conformance
/// (`HubDataProvider+WorkoutTemplates.swift`). Same `HubClientTests`-extension convention as
/// `HubDataProviderKpiTargetsTests.swift` (StubURLProtocol's process-global state, run serially).
extension HubClientTests {
    private func workoutTemplatesProvider(baseURL: String = "http://hub.test:8000", token: String = "t0k") -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: baseURL)!, token: token)
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func workoutTemplatesGetsContractRouteWithBearerAndDecodesRows() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/workout-templates"] = (200, Data("""
        [{"template_id": 2, "name": "Norwegian 4×4", "activity": "running", "location": "outdoor", "weekdays": [1, 5], "steps": [{"purpose": "warmup", "seconds": 600, "hr_lo": 100, "hr_hi": 140, "repeat": 1}, {"purpose": "work", "seconds": 240, "hr_lo": 160, "hr_hi": 175, "repeat": 4}, {"purpose": "recovery", "seconds": 180, "hr_lo": 100, "hr_hi": 140, "repeat": 4}, {"purpose": "cooldown", "seconds": 300, "hr_lo": 100, "hr_hi": 140, "repeat": 1}], "updated_at": "2026-09-21T00:00:00Z"}]
        """.utf8))
        let templates = try await workoutTemplatesProvider().workoutTemplates()
        #expect(templates.count == 1)
        #expect(templates[0].templateId == 2)
        #expect(templates[0].location == .outdoor)
        #expect(templates[0].steps.count == 4)
        #expect(templates[0].steps[1].purpose == .work && templates[0].steps[1].repeat == 4)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "GET")
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/planning/workout-templates")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t0k")
    }

    @Test func workoutTemplatesMapsStatusToNamedErrors() async {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/workout-templates"] = (401, Data("{\"detail\":\"unauthorized\"}".utf8))
        await #expect(throws: HubError.self) {
            _ = try await self.workoutTemplatesProvider().workoutTemplates()
        }
    }
}

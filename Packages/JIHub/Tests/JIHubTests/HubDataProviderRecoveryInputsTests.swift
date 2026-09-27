import Foundation
import Testing
import JICore
@testable import JIHub

/// B-57 W3 D1 — `GET /api/v1/vitals/recovery-inputs` (HT `app/vitals/router.py::get_recovery_inputs`,
/// body = `{"date", "days": inputs_to_json(load_recovery_inputs(...))}` — the gate's own loader).
extension HubClientTests {
    private func recoveryProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func recoveryInputsGetsWithDateAndWindowAndDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/vitals/recovery-inputs"] = (200, Data("""
        {"date":"2026-09-24","days":[
          {"date":"2026-09-23","hrv_ms":41.0,"rhr_bpm":56.0,"sleep_h":7.25,"deep_h":1.1,"rem_h":1.7,"load_min":null},
          {"date":"2026-09-24","hrv_ms":null,"rhr_bpm":null,"sleep_h":null,"deep_h":null,"rem_h":null,"load_min":40.0}]}
        """.utf8))
        let days = try await recoveryProvider().recoveryInputs(date: "2026-09-24", windowDays: 42)
        #expect(days.count == 2)
        #expect(days[0] == RecoveryInputDay(date: "2026-09-23", hrvMs: 41, rhrBpm: 56, sleepH: 7.25, deepH: 1.1, remH: 1.7, loadMin: nil))
        #expect(days[1].hrvMs == nil && days[1].loadMin == 40)
        let url = try #require(StubURLProtocol.lastRequest?.url)
        #expect(url.path == "/api/v1/vitals/recovery-inputs")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "date", value: "2026-09-24")))
        #expect(items.contains(URLQueryItem(name: "window_days", value: "42")))
    }

    /// The route validates `window_days` in 1…365 (422 outside) — the client clamps, never asks for more.
    @Test func recoveryInputsClampsWindowToTheRouteBounds() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/vitals/recovery-inputs"] = (200, Data(#"{"date":"2026-09-24","days":[]}"#.utf8))
        let days = try await recoveryProvider().recoveryInputs(date: "2026-09-24", windowDays: 900)
        #expect(days.isEmpty)
        let url = try #require(StubURLProtocol.lastRequest?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "window_days", value: "365")))
        _ = try await recoveryProvider().recoveryInputs(date: "2026-09-24", windowDays: 0)
        let url0 = try #require(StubURLProtocol.lastRequest?.url)
        #expect((URLComponents(url: url0, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .contains(URLQueryItem(name: "window_days", value: "1")))
    }
}

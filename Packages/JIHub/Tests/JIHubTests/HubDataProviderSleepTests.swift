import Foundation
import Testing
import JICore
@testable import JIHub

/// W-FIX2 L5 (FM-08 app side, DEV-02): `/vitals/sleep-summary` is called and decoded. The body is
/// the route's shape as served on 2026-09-25 (`routes/api_v1_vitals_sleep-summary.json`, W-REG1).
extension HubClientTests {
    private func sleepProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    @Test func sleepSummaryDecodesTheServedShape() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/vitals/sleep-summary"] = (200, Data("""
        {"score_computed":89,"score_computed_date":"2026-09-25","score_computed_source":"AppleHealth",
         "debt_hours":-3.89,"debt_baseline_hours":7.399,"debt_date":"2026-09-25","debt_source":"AppleHealth",
         "bedtime_consistency_sd_min":null,"bedtime_consistency_nights":0,"bedtime_consistency_sources":[],
         "last_night_date":"2026-09-25","last_night_duration_sec":30895,"last_night_deep_sleep_sec":2637,
         "last_night_light_sleep_sec":20677,"last_night_rem_sleep_sec":7581,"last_night_source":"AppleHealth"}
        """.utf8))
        let s = try await sleepProvider().sleepSummary()
        #expect(StubURLProtocol.lastRequest?.url?.path == "/api/v1/vitals/sleep-summary")
        #expect(s.scoreComputed == 89)
        #expect(s.scoreComputedDate == "2026-09-25")
        #expect(s.scoreComputedSource == "AppleHealth")
        #expect(s.debtHours == -3.89)
        #expect(s.lastNightDate == "2026-09-25")
        #expect(s.lastNightDurationSec == 30895)
        #expect(s.lastNightDeepSleepSec == 2637)
        #expect(s.lastNightRemSleepSec == 7581)
        #expect(s.bedtimeConsistencySdMin == nil)
    }

    @Test func sleepSummaryAllNullDecodesToNils() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/vitals/sleep-summary"] = (200, Data("""
        {"score_computed":null,"score_computed_date":null,"last_night_date":null}
        """.utf8))
        let s = try await sleepProvider().sleepSummary()
        #expect(s.scoreComputed == nil)
        #expect(s.lastNightDurationSec == nil)
    }
}

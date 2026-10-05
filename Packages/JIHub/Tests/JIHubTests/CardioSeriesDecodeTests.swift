import Foundation
import Testing
import JICore
@testable import JIHub

/// B-94 b94p3 (BP-4) — `GET /api/v1/training/cardio-series` decodes. Payload = a real hub answer
/// (ht_b94p3 throwaway DB, range=90d: 17 runs, trimmed to 2 runs + 2 VO2 max points).
/// Nested in `HubClientTests` so it inherits that suite's `.serialized` (StubURLProtocol is global).
extension HubClientTests {
    @Suite struct CardioSeriesDecodeTests {
        static let payload = """
        {"range":"90d","from":"2026-07-07","to":"2026-10-05","runs":[{"activity_id":23531041524,"date":"2026-07-09","type":"treadmill_running","source":"garmin","distance_m":6049.4,"duration_sec":3614,"pace_sec_per_km":597.4,"avg_hr":121},{"activity_id":8000000000000015,"date":"2026-09-29","type":"running","source":"apple","distance_m":4784.6,"duration_sec":2602,"pace_sec_per_km":543.8,"avg_hr":143}],"vo2max":[{"date":"2026-07-22","vo2max":39.6,"source":"garmin"},{"date":"2026-07-23","vo2max":39.3,"source":"garmin"}]}
        """

        private func provider() -> HubDataProvider {
            let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8281")!, token: "t0k")
            return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
        }

        @Test func sendsTheRangeAndDecodesRunsAndVo2max() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.responses["/api/v1/training/cardio-series"] = (200, Data(Self.payload.utf8))
            let s = try await provider().cardioSeries(range: "90d")
            #expect(s.range == "90d" && s.from == "2026-07-07" && s.to == "2026-10-05")
            #expect(s.runs.count == 2)
            let first = try #require(s.runs.first)
            #expect(first.activityId == 23531041524 && first.type == "treadmill_running" && first.source == "garmin")
            #expect(first.distanceM == 6049.4 && first.durationSec == 3614 && first.paceSecPerKm == 597.4 && first.avgHr == 121)
            #expect(s.runs.last?.activityId == 8000000000000015 && s.runs.last?.source == "apple")
            #expect(s.vo2max == [Vo2maxPoint(date: "2026-07-22", vo2max: 39.6, source: "garmin"),
                                 Vo2maxPoint(date: "2026-07-23", vo2max: 39.3, source: "garmin")])
            let url = try #require(StubURLProtocol.lastRequest?.url)
            #expect(url.path == "/api/v1/training/cardio-series" && url.query == "range=90d")
        }

        @Test func nullHeartRateAndEmptySeriesDecode() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.responses["/api/v1/training/cardio-series"] = (200, Data("""
            {"range":"w","from":"2026-09-28","to":"2026-10-05","runs":[{"activity_id":1,"date":"2026-09-30","type":"running","source":"apple","distance_m":1000.0,"duration_sec":360,"pace_sec_per_km":360.0,"avg_hr":null}],"vo2max":[]}
            """.utf8))
            let s = try await provider().cardioSeries(range: "w")
            #expect(s.runs.first?.avgHr == nil && s.vo2max.isEmpty)
        }

        @Test func unauthorizedThrows() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.responses["/api/v1/training/cardio-series"] = (401, Data("{\"detail\":\"unauthorized\"}".utf8))
            await #expect(throws: (any Error).self) { _ = try await provider().cardioSeries(range: "90d") }
        }
    }
}

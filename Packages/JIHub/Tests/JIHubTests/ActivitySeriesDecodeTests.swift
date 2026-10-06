import Foundation
import Testing
import JICore
@testable import JIHub

/// W-B98A B98-4 — `GET /api/v1/training/activity/{id}/series` decodes. Payloads = real hub answers
/// (throwaway hub :8812 at HT b98p2, prod DB read-only, 2026-10-06), trimmed to 2 splits / a few points.
/// Nested in `HubClientTests` so it inherits that suite's `.serialized` (StubURLProtocol is global).
extension HubClientTests {
    @Suite struct ActivitySeriesDecodeTests {
        static let garmin = """
        {"activity_id":23926763203,"type":"running","splits":[{"km":1,"distance_m":1000.0,"duration_s":840.55,"pace_s_per_km":840.55,"mean_hr":121.1,"elevation_gain_m":7.3},{"km":2,"distance_m":1000.0,"duration_s":777.01,"pace_s_per_km":777.01,"mean_hr":124.2,"elevation_gain_m":5.3}],"points":[{"t":720.0,"hr":124.5,"pace_s_per_km":771.0},{"t":736.0,"hr":125.9,"pace_s_per_km":767.2},{"t":752.0,"hr":123.6,"pace_s_per_km":757.0}],"hr_only":false,"caption":"JI-computed, may differ from Garmin"}
        """
        static let appleHrOnly = """
        {"activity_id":8000000000000009,"type":"running","splits":[],"points":[{"t":0.0,"hr":117.0,"pace_s_per_km":null},{"t":1.0,"hr":120.0,"pace_s_per_km":null}],"hr_only":true,"caption":"JI-computed, may differ from Garmin"}
        """

        private func provider() -> HubDataProvider {
            let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8281")!, token: "t0k")
            return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
        }

        @Test func requestsTheActivityPathAndDecodesSplitsAndPoints() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.responses["/api/v1/training/activity/23926763203/series"] = (200, Data(Self.garmin.utf8))
            let s = try await provider().activitySeries(activityId: 23926763203)
            #expect(s.activityId == 23926763203 && s.type == "running" && !s.hrOnly)
            #expect(s.caption == "JI-computed, may differ from Garmin")
            #expect(s.splits.count == 2)
            #expect(s.splits.first == ActivitySplit(km: 1, distanceM: 1000, durationS: 840.55, paceSPerKm: 840.55, meanHr: 121.1, elevationGainM: 7.3))
            #expect(s.points.count == 3 && s.points.first == ActivitySeriesPoint(t: 720, hr: 124.5, paceSPerKm: 771))
            let url = try #require(StubURLProtocol.lastRequest?.url)
            #expect(url.path == "/api/v1/training/activity/23926763203/series")
        }

        @Test func appleGpsLessRunIsHrOnly() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.responses["/api/v1/training/activity/8000000000000009/series"] = (200, Data(Self.appleHrOnly.utf8))
            let s = try await provider().activitySeries(activityId: 8000000000000009)
            #expect(s.hrOnly && s.splits.isEmpty && s.points.allSatisfy { $0.paceSPerKm == nil })
        }

        @Test func unknownIdThrowsThe404() async throws {
            StubURLProtocol.reset()
            StubURLProtocol.responses["/api/v1/training/activity/1/series"] = (404, Data("{\"detail\":\"activity not found\"}".utf8))
            await #expect(throws: (any Error).self) { _ = try await provider().activitySeries(activityId: 1) }
        }
    }
}

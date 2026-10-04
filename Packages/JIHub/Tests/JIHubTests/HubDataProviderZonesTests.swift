import Foundation
import Testing
import JICore
@testable import JIHub

/// B-95 (BP-26) — `GET /api/v1/training/zones` decodes (payload = a real hub answer, ht_b95 throwaway DB).
extension HubClientTests {
    @Test func trainingZonesSendsTheRangeAndDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/training/zones"] = (200, Data("""
        {"from":"2026-08-17","to":"2026-08-23","bucket":"week","scope":"cardio","floors":[97,117,139,160,176],"hr_cap_bpm":175,"buckets":[{"start":"2026-08-17","minutes":[50.5,60.4,15.2,19.0,0.7],"sessions":3,"sessions_no_hr":0}],"totals":{"minutes":[50.5,60.4,15.2,19.0,0.7],"sessions":3,"sessions_no_hr":0},"sources":{"samples":3,"zone_time":0}}
        """.utf8))
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8281")!, token: "t0k")
        let p = HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
        let r = try await p.trainingZones(from: "2026-08-17", to: "2026-08-23", bucket: "week", scope: "cardio")
        #expect(r.floors == [97, 117, 139, 160, 176] && r.hrCapBpm == 175)
        #expect(r.buckets.first?.minutes == [50.5, 60.4, 15.2, 19.0, 0.7] && r.buckets.first?.sessionsNoHr == 0)
        #expect(r.totals.sessions == 3)
        let url = try #require(StubURLProtocol.lastRequest?.url)
        #expect(url.query?.contains("bucket=week") == true && url.query?.contains("from=2026-08-17") == true)
    }
}

import Foundation
import Testing
import JICore
@testable import JIHub

/// W-TGT L1 — `GET/PUT /api/v1/planning/targets` (the one mirror body, spec §3).
extension HubClientTests {
    private func targetsProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    private func targetsBody(_ request: URLRequest?) throws -> [String: Any] {
        var data = Data()
        if let stream = request?.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        } else {
            data = try #require(request?.httpBody)
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let answer = """
    {"version":1,"updated_at":"2026-09-28T05:00:00+00:00",
     "goals":{"weight":null,"kcal":{"goal_kcal":1617,"basis":"includes_deficit","deficit_kcal_per_day":null,"weekly_loss_kg":null,"target_kcal":1617},
              "protein_g":155,"carbs_g":null,"fat_g":null,"steps_daily":null,"sleep_h":null,"strength":[]},
     "limits":{"hr_cap_bpm":175,"hr_cap_confirmed_on":null,"zones":null,"avoid_zone5":false},
     "rules":{"hrv_low_nights":2,"resp_delta_amber":null,"carb_three_day_floor":null,"interval_min_sleep":null,
              "load_over":1.3,"load_under":0.8,"load_band_low":0.8,"load_band_high":1.3,
              "week_kcal_floor":1600,"week_protein_floor":130,"week_sleep_score_floor":55}}
    """

    @Test func putTargetsSendsTheSnakeCaseDocumentAndDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/targets"] = (200, Data(Self.answer.utf8))
        var doc = TargetsDocument.empty
        doc.goals.kcal = KcalGoal(goalKcal: 1617, basis: .includesDeficit)
        doc.goals.proteinG = 155
        doc.limits.hrCapBpm = 175
        doc.rules[.hrvLowNights] = 2
        let out = try await targetsProvider().putTargets(doc)
        #expect(out.goal(.kcal) == 1617 && out.limit(.hrCap) == 175 && out.rules[.weekKcalFloor] == 1600)
        let req = try #require(StubURLProtocol.lastRequest)
        #expect(req.httpMethod == "PUT")
        #expect(req.url?.path == "/api/v1/planning/targets")
        let body = try targetsBody(req)
        let goals = try #require(body["goals"] as? [String: Any])
        #expect(goals["protein_g"] as? Double == 155)
        #expect(goals["sleep_h"] is NSNull)
        let limits = try #require(body["limits"] as? [String: Any])
        #expect(limits["hr_cap_bpm"] as? Int == 175)
        #expect(limits["hrCapBpm"] == nil)
        let rules = try #require(body["rules"] as? [String: Any])
        #expect(rules["hrv_low_nights"] as? Int == 2)
        #expect(rules["week_kcal_floor"] is NSNull)
    }

    @Test func getTargetsDecodesTheHubDocument() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/targets"] = (200, Data(Self.answer.utf8))
        let out = try await targetsProvider().targets()
        #expect(out.goals.kcal?.basis == .includesDeficit && out.goal(.sleep) == nil)
        #expect(StubURLProtocol.lastRequest?.httpMethod == "GET")
    }
}

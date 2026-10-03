import Foundation
import Testing
import JICore
@testable import JIHub

/// W-B38-A A-8 — `HubDataProvider+Strength.swift` against the card's route shapes (A-2..A-4).
extension HubClientTests {
    private func strengthProvider() -> HubDataProvider {
        let config = ConnectionConfig(baseURL: URL(string: "http://hub.test:8000")!, token: "t0k")
        return HubDataProvider(client: HubClient(config: config, session: StubURLProtocol.session()))
    }

    private func body(_ request: URLRequest?) throws -> [String: Any] {
        var data = Data()
        if let stream = request?.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
        } else { data = try #require(request?.httpBody) }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func createStrengthSessionPostsSnakeCaseBodyAndDecodesTheId() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["POST /api/v1/planning/strength-sessions"] = (201, Data("""
        {"session_log_id": 12, "client_id": "c-1", "session_id": 3, "date": "2026-10-03", "started_at": "2026-10-03T07:00:00+00:00", "ended_at": null}
        """.utf8))
        let out = try await strengthProvider().createStrengthSession(
            StrengthSessionCreate(clientId: "c-1", date: "2026-10-03", startedAt: "2026-10-03T07:00:00Z", sessionId: 3))
        #expect(out.sessionLogId == 12 && out.clientId == "c-1")
        let sent = try body(StubURLProtocol.lastRequest)
        #expect(sent["client_id"] as? String == "c-1")
        #expect(sent["started_at"] as? String == "2026-10-03T07:00:00Z")
        #expect(sent["session_id"] as? Int == 3)
    }

    @Test func logEditDeleteSetHitTheKeyedRoutes() async throws {
        StubURLProtocol.reset()
        let set = StrengthSetIn(clientId: "s-1", exerciseKey: "Barbell Bench Press", exerciseId: 7, setIndex: 1, kind: "reps",
                                reps: 8, weightKg: 52.5, durationS: nil, rpe: 8, performedAt: "2026-10-03T07:05:00Z")
        StubURLProtocol.methodResponses["POST /api/v1/planning/strength-sessions/12/sets"] = (201, Data(#"{"set_log_id": 5, "client_id": "s-1"}"#.utf8))
        StubURLProtocol.methodResponses["PUT /api/v1/planning/strength-sessions/12/sets/s-1"] = (200, Data(#"{"set_log_id": 5}"#.utf8))
        StubURLProtocol.methodResponses["DELETE /api/v1/planning/strength-sessions/12/sets/s-1"] = (204, Data())
        let p = strengthProvider()
        let ack = try await p.logStrengthSet(sessionLogId: 12, set)
        #expect(ack.setLogId == 5)
        let sent = try body(StubURLProtocol.lastRequest)
        #expect(sent["exercise_key"] as? String == "Barbell Bench Press")
        #expect(sent["weight_kg"] as? Double == 52.5 && sent["set_index"] as? Int == 1 && sent["rpe"] as? Double == 8)
        _ = try await p.updateStrengthSet(sessionLogId: 12, clientId: "s-1", set)
        try await p.deleteStrengthSet(sessionLogId: 12, clientId: "s-1")
        #expect(StubURLProtocol.log == [
            "POST /api/v1/planning/strength-sessions/12/sets",
            "PUT /api/v1/planning/strength-sessions/12/sets/s-1",
            "DELETE /api/v1/planning/strength-sessions/12/sets/s-1",
        ])
    }

    @Test func completeSendsTheExplicitAdvanceList() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["POST /api/v1/planning/strength-sessions/12/complete"] = (200, Data(#"{"session_log_id": 12, "ended_at": "2026-10-03T08:00:00+00:00"}"#.utf8))
        _ = try await strengthProvider().completeStrengthSession(sessionLogId: 12, StrengthSessionComplete(
            endedAt: "2026-10-03T08:00:00Z", advance: [StrengthAdvance(exerciseId: 7, currentWeightKg: 55)]))
        let sent = try body(StubURLProtocol.lastRequest)
        let advance = try #require(sent["advance"] as? [[String: Any]])
        #expect(advance.count == 1)
        #expect(advance[0]["exercise_id"] as? Int == 7 && advance[0]["current_weight_kg"] as? Double == 55)
    }

    /// X-1 (A-6 XC half): a zero / non-finite advance never leaves the phone.
    @Test func completeWithAZeroAdvanceIsRefusedBeforeSending() async throws {
        StubURLProtocol.reset()
        await #expect(throws: StrengthAdvanceWouldClear(exerciseId: 7)) {
            _ = try await self.strengthProvider().completeStrengthSession(sessionLogId: 12, StrengthSessionComplete(
                endedAt: "2026-10-03T08:00:00Z", advance: [StrengthAdvance(exerciseId: 7, currentWeightKg: 0)]))
        }
        #expect(StubURLProtocol.log.isEmpty)
    }

    @Test func emptyAdvanceIsSentAsAnEmptyList() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.methodResponses["POST /api/v1/planning/strength-sessions/12/complete"] = (200, Data("{}".utf8))
        _ = try await strengthProvider().completeStrengthSession(sessionLogId: 12, StrengthSessionComplete(endedAt: "2026-10-03T08:00:00Z", advance: []))
        #expect((try body(StubURLProtocol.lastRequest)["advance"] as? [Any])?.isEmpty == true)
    }

    @Test func historyAndLastSetsDecodeBareArraysAndEnvelopes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.responses["/api/v1/planning/strength-sessions"] = (200, Data("""
        [{"session_log_id": 12, "client_id": "c-1", "date": "2026-10-03", "started_at": "2026-10-03T07:00:00+00:00",
          "sets": [{"client_id": "s-1", "exercise_key": "Barbell Bench Press", "set_index": 1, "kind": "reps", "reps": 8, "weight_kg": 52.5, "performed_at": "2026-10-03T07:05:00+00:00"}]}]
        """.utf8))
        StubURLProtocol.responses["/api/v1/planning/strength-sessions/last-sets"] = (200, Data("""
        {"exercise_key": "Barbell Bench Press", "sets": [{"exercise_key": "Barbell Bench Press", "set_index": 1, "reps": 8, "weight_kg": 50}]}
        """.utf8))
        let p = strengthProvider()
        let history = try await p.strengthSessions(from: "2026-09-01", to: "2026-10-03")
        #expect(history.count == 1 && history[0].sets?.first?.weightKg == 52.5)
        let q = StubURLProtocol.lastRequest?.url?.query ?? ""
        #expect(q.contains("from=2026-09-01") && q.contains("to=2026-10-03"))
        let last = try await p.strengthLastSets(exerciseKey: "Barbell Bench Press")
        #expect(last.first?.weightKg == 50)
        #expect(StubURLProtocol.lastRequest?.url?.query?.contains("exercise_key=Barbell") == true)
    }
}

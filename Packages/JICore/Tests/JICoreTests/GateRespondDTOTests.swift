import Foundation
import Testing
@testable import JICore

/// W5b-L4 — wire-shape tests for `DTOs/GateRespond.swift`, in place of a captured fixture: both
/// routes are POSTs answering with a server-assigned id, so the shapes come straight from HT's
/// `GateRespondOut` / `FeelOut` (`app/planning/router.py:318,354`) and the RN oracle's
/// `GateRespondResult` / `FeelResult` (`mobile/src/data/types.ts:117,122`).

@Test func gateRespondResultDecodesTheRoutersOut() throws {
    let out = try JSON.decoder.decode(GateRespondResult.self, from: Data(#"{"pdf_requested":true,"log_id":41}"#.utf8))
    #expect(out == GateRespondResult(pdfRequested: true, logId: 41))
}

@Test func gateRespondResultKeepsNullLogIdNil() throws {
    let out = try JSON.decoder.decode(GateRespondResult.self, from: Data(#"{"pdf_requested":false,"log_id":null}"#.utf8))
    #expect(out.logId == nil)
    #expect(out.pdfRequested == false)
}

@Test func feelResultDecodesTheRoutersOut() throws {
    let out = try JSON.decoder.decode(FeelResult.self, from: Data(#"{"feel_id":7}"#.utf8))
    #expect(out == FeelResult(feelId: 7))
}

@Test func gateChoiceRawValuesMatchTheRoutersLiteral() {
    #expect(GateChoice.yes.rawValue == "y")
    #expect(GateChoice.skip.rawValue == "N")
    #expect(GateChoice.override.rawValue == "override")
    #expect(GateChoice.allCases.count == 3)
}

/// The bodies round-trip through a plain `JSONEncoder`/`JSONDecoder` pair (the `Outbox` storage
/// format) without losing their snake_case wire keys.
@Test func bodiesRoundTripThroughPlainCoders() throws {
    let respond = GateRespondBody(choice: .override, overrideReason: "Schedule constraint", windowDays: 14)
    let respondData = try JSONEncoder().encode(respond)
    #expect(try JSONDecoder().decode(GateRespondBody.self, from: respondData) == respond)
    let respondJSON = try JSONSerialization.jsonObject(with: respondData) as? [String: Any]
    #expect(respondJSON?["override_reason"] as? String == "Schedule constraint")
    #expect(respondJSON?["window_days"] as? Int == 14)

    let feel = FeelBody(feelScore: 5, notes: "", date: "2026-09-18")
    let feelData = try JSONEncoder().encode(feel)
    #expect(try JSONDecoder().decode(FeelBody.self, from: feelData) == feel)
    let feelJSON = try JSONSerialization.jsonObject(with: feelData) as? [String: Any]
    #expect(feelJSON?["feel_score"] as? Int == 5)
}

/// W-B29 R-2 — the write-path fixtures of record (`planning_gate_respond.json` /
/// `planning_feel.json`, `{request, response}` captured from a throwaway hub by
/// `capture_hub_fixtures.py --writes`) decode through the DTOs, and the mock serves them.
private struct WriteFixture<Request: Decodable, Response: Decodable> {
    let request: Request
    let response: Response
}

/// Request bodies carry explicit snake_case `CodingKeys` (plain `JSONDecoder`, the `Outbox`
/// format); responses decode through `JSON.decoder` exactly as `HubClient` does.
private func loadWriteFixture<Req: Decodable, Res: Decodable>(_ name: String, _: Req.Type, _: Res.Type) throws -> WriteFixture<Req, Res> {
    let url = try #require(MockDataProvider.fixtureURL(named: name), "missing fixture \(name)")
    let doc = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let request = try JSONSerialization.data(withJSONObject: try #require(doc["request"]))
    let response = try JSONSerialization.data(withJSONObject: try #require(doc["response"]))
    return WriteFixture(request: try JSONDecoder().decode(Req.self, from: request),
                        response: try JSON.decoder.decode(Res.self, from: response))
}

@Test func testFixtureRoundTrip() throws {
    let respond = try loadWriteFixture("planning_gate_respond", GateRespondBody.self, GateRespondResult.self)
    #expect(respond.request.choice == .skip)
    #expect(respond.request.windowDays == 7)
    #expect(respond.response.logId != nil)
    #expect(respond.response.pdfRequested == false)   // hub rule: choice N → no PDF
    let reencoded = try JSONDecoder().decode(GateRespondBody.self, from: JSONEncoder().encode(respond.request))
    #expect(reencoded == respond.request)

    let feel = try loadWriteFixture("planning_feel", FeelBody.self, FeelResult.self)
    #expect(feel.request.feelScore == 3)
    #expect(feel.request.date == "2026-10-04")
    #expect(feel.response.feelId > 0)
}

@Test func mockServesTheWriteFixtureResponses() async throws {
    let respond = try loadWriteFixture("planning_gate_respond", GateRespondBody.self, GateRespondResult.self)
    let feel = try loadWriteFixture("planning_feel", FeelBody.self, FeelResult.self)
    let mock = MockDataProvider()
    let skip = try await mock.respondGate(choice: .skip, overrideReason: "", windowDays: 7)
    #expect(skip == respond.response)
    let yes = try await mock.respondGate(choice: .yes, overrideReason: "", windowDays: 7)
    #expect(yes.logId == respond.response.logId)
    #expect(yes.pdfRequested == true)   // hub rule: y/override → PDF
    #expect(try await mock.logFeel(feelScore: 3, notes: "", date: nil) == feel.response)
}

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

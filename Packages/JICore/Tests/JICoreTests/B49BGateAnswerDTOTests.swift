import Foundation
import Testing
@testable import JICore

// W-B49B G-3: `/planning/morning` carries `gate_answer` — the hub's automatic answer (source
// "auto", FULL/GATED + the workout) or the user's manual one. Optional: an older hub omits it.
@Test func morningDecodesAnAutomaticGateAnswer() throws {
    let json = Data(#"""
    {"today_activities":[],"carb_watch_floor":150,"hrv_series":[],
     "gate_answer":{"log_id":12,"date":"2026-09-29","choice":"N","source":"auto",
                    "classification":"GATED","workout":"Easy Run","logged_at":"2026-09-29T07:10:00+02:00"}}
    """#.utf8)
    let m = try JSON.decoder.decode(MorningResponse.self, from: json)
    let a = try #require(m.gateAnswer)
    #expect(a.logId == 12 && a.date == "2026-09-29")
    #expect(a.gateChoice == .skip)
    #expect(a.isAutomatic)
    #expect(a.classification == "GATED" && a.workout == "Easy Run")
}

@Test func morningWithoutGateAnswerDecodesNil() throws {
    let json = Data(#"{"today_activities":[],"carb_watch_floor":150,"hrv_series":[]}"#.utf8)
    #expect(try JSON.decoder.decode(MorningResponse.self, from: json).gateAnswer == nil)
    let nulled = Data(#"{"today_activities":[],"carb_watch_floor":150,"hrv_series":[],"gate_answer":null}"#.utf8)
    #expect(try JSON.decoder.decode(MorningResponse.self, from: nulled).gateAnswer == nil)
}

@Test func manualGateAnswerIsNotAutomaticAndAnUnknownValueNeverBreaksTheMorning() throws {
    let manual = Data(#"{"log_id":3,"date":"2026-09-29","choice":"y","source":"manual","classification":null,"workout":null,"logged_at":null}"#.utf8)
    let a = try JSON.decoder.decode(GateAnswer.self, from: manual)
    #expect(!a.isAutomatic && a.gateChoice == .yes)
    let odd = Data(#"{"log_id":4,"date":"2026-09-29","choice":"maybe","source":"robot"}"#.utf8)
    let b = try JSON.decoder.decode(GateAnswer.self, from: odd)
    #expect(b.gateChoice == nil && !b.isAutomatic)
}

@Test func automaticAnswerLineNamesTheClassAndTheWorkout() {
    let auto = GateAnswer(logId: 1, date: "2026-09-29", choice: "N", source: "auto", classification: "GATED", workout: "Easy Run")
    #expect(gateAnswerLine(auto) == "Answered automatically · GATED from Easy Run")
    let full = GateAnswer(logId: 2, date: "2026-09-29", choice: "y", source: "auto", classification: "FULL", workout: nil)
    #expect(gateAnswerLine(full) == "Answered automatically · FULL")
    let manual = GateAnswer(logId: 3, date: "2026-09-29", choice: "y", source: "manual")
    #expect(gateAnswerLine(manual) == nil)
    #expect(gateAnswerLine(nil) == nil)
}

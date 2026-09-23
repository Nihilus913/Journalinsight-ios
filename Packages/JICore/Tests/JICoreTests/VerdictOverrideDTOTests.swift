import Foundation
import Testing
@testable import JICore

// W-B57b — `/planning/morning`'s two optional fields + the verdict-override DTOs, decoded from the
// literal snake_case wire shape the Wave Card's Contract pins.

private let morningBase = #"""
"today_activities": [], "verdict": "MODIFIED — Easy Z2 30–40 min", "verdict_date": "2026-09-23",
"experiment": null, "carbs_3d_avg": 150.0, "carb_watch_floor": 120, "hrv_series": []
"""#

@Test func morningDecodesWithoutTheW_B57bFields() throws {
    let m = try JSON.decoder.decode(MorningResponse.self, from: Data("{\(morningBase)}".utf8))
    #expect(m.gateSignals == nil)
    #expect(m.verdictOverride == nil)
    #expect(m.carbs3dAvg == 150.0)
}

@Test func morningDecodesExplicitNullW_B57bFields() throws {
    let m = try JSON.decoder.decode(MorningResponse.self, from: Data(
        "{\(morningBase), \"gate_signals\": null, \"verdict_override\": null}".utf8))
    #expect(m.gateSignals == nil)
    #expect(m.verdictOverride == nil)
}

@Test func morningDecodesGateSignalsAndVerdictOverrideFromTheWire() throws {
    let json = Data(#"""
    {\#(morningBase),
     "gate_signals": [
      {"key":"sleep","label":"Sleep","value":74,"unit":"","threshold":70,"direction":"min","scale_min":0,"scale_max":100,"status":"pass","note":null},
      {"key":"hrv","label":"HRV","value":24.5,"unit":"ms","threshold":27,"direction":"min","scale_min":0,"scale_max":80,"status":"amber","note":"HRV 24.5 — under 27"},
      {"key":"rhr","label":"RHR","value":null,"unit":"bpm","threshold":65,"direction":"max","scale_min":40,"scale_max":80,"status":"missing","note":"overnight vitals not synced yet"},
      {"key":"sleep_h","label":"Sleep time","value":5.4,"unit":"h","threshold":6.0,"direction":"min","scale_min":0,"scale_max":10,"status":"amber","note":"sleep 5.4 h — under 6.0"}
     ],
     "verdict_override": {"date":"2026-09-23","choice":"full","reason":"Feel good despite metrics","session":"Full Upper","created_at":"2026-09-23T06:01:00+02:00"}}
    """#.utf8)
    let m = try JSON.decoder.decode(MorningResponse.self, from: json)
    let s = try #require(m.gateSignals)
    #expect(s.map(\.key) == ["sleep", "hrv", "rhr", "sleep_h"])
    #expect(s[0] == GateSignal(key: "sleep", label: "Sleep", value: 74, unit: "", threshold: 70,
                               direction: .min, scaleMin: 0, scaleMax: 100, status: .pass, note: nil))
    #expect(s[1].status == .amber && s[1].value == 24.5 && s[1].note == "HRV 24.5 — under 27")
    #expect(s[2].value == nil && s[2].status == .missing && s[2].direction == .max && s[2].scaleMin == 40)
    #expect(s[3].threshold == 6.0 && s[3].unit == "h")
    #expect(m.verdictOverride == VerdictOverride(date: "2026-09-23", choice: .full, reason: "Feel good despite metrics",
                                                 session: "Full Upper", createdAt: "2026-09-23T06:01:00+02:00"))
}

@Test func morningWithW_B57bFieldsRoundTripsThroughTheCacheEncoderDecoderPair() throws {
    let json = Data(#"""
    {\#(morningBase),
     "gate_signals": [{"key":"hrv","label":"HRV","value":24.5,"unit":"ms","threshold":27,"direction":"min","scale_min":0,"scale_max":80,"status":"red","note":null}],
     "verdict_override": {"date":"2026-09-23","choice":"rest","reason":null,"session":"Rest — walks only","created_at":null}}
    """#.utf8)
    let m = try JSON.decoder.decode(MorningResponse.self, from: json)
    #expect(try JSON.decoder.decode(MorningResponse.self, from: JSON.encoder.encode(m)) == m)
}

@Test func unknownSignalStatusAndDirectionDegradeInsteadOfFailingTheMorning() throws {
    let json = Data(#"""
    {"key":"hrv","label":"HRV","value":30,"unit":"ms","threshold":27,"direction":"between","scale_min":0,"scale_max":80,"status":"purple"}
    """#.utf8)
    let s = try JSON.decoder.decode(GateSignal.self, from: json)
    #expect(s.status == .missing)
    #expect(s.direction == .min)
    #expect(s.note == nil)
}

@Test func verdictOverrideBodyEncodesTheWireKeys() throws {
    let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
        VerdictOverrideBody(date: "2026-09-23", choice: .modified, reason: "Schedule constraint"))) as? [String: Any]
    #expect(obj?["date"] as? String == "2026-09-23")
    #expect(obj?["choice"] as? String == "modified")
    #expect(obj?["reason"] as? String == "Schedule constraint")
    #expect(obj?.count == 3)
}

@Test func verdictOverrideChoiceRawValuesMatchTheHubCheckConstraint() {
    #expect(VerdictOverrideChoice.allCases.map(\.rawValue) == ["accept", "full", "modified", "rest"])
}

@Test func mockProviderEchoesAVerdictOverride() async throws {
    let o = try await MockDataProvider().setVerdictOverride(date: "2026-09-23", choice: .rest, reason: "")
    #expect(o.choice == .rest && o.session == "Rest — walks only" && o.reason == nil && o.date == "2026-09-23")
}

// B-65 — daytime HRV arrives as a `context` arc (shown, never gating).
@Test func contextStatusDecodes() throws {
    let s = try JSONDecoder().decode(GateSignalStatus.self, from: Data("\"context\"".utf8))
    #expect(s == .context)
}

@Test func unknownStatusStillDecodesAsMissing() throws {
    let s = try JSONDecoder().decode(GateSignalStatus.self, from: Data("\"weird\"".utf8))
    #expect(s == .missing)
}

@Test func appleNightHrvDayContextArcDecodes() throws {
    let json = Data(#"""
    {"key":"hrv_day","label":"HRV (day)","value":31,"unit":"ms","threshold":0,"direction":"min","scale_min":0,"scale_max":80,"status":"context","note":"weekday — dosed"}
    """#.utf8)
    let s = try JSON.decoder.decode(GateSignal.self, from: json)
    #expect(s.status == .context)
    #expect(s.value == 31)
    #expect(s.note == "weekday — dosed")
}

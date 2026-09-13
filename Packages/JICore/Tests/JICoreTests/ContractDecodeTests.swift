import Foundation
import Testing
@testable import JICore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources/hub-contract"))
    return try Data(contentsOf: url)
}

@Test func decodesGate() throws {
    let g = try JSON.decoder.decode(GateResponse.self, from: fixture("planning_gate"))
    #expect(g.daily.count == g.totalDays)
    #expect([.progress, .maintain, .reduce, .insufficientData].contains(g.recommendation))
}

/// Regression for `Dictionary`'s subscript-assign-nil-removes-the-key gotcha: a JSON `null` column
/// (e.g. `kcal_consumed` on several rows of `planning_gate.json`, when a day has no logged meals)
/// must stay present in `DailyKpiRow.values` as `.some(nil)`, not vanish from the dictionary.
@Test func dailyKpiRowKeepsNullColumnsPresentWithNil() throws {
    let g = try JSON.decoder.decode(GateResponse.self, from: fixture("planning_gate"))
    let nullRow = try #require(g.daily.first {
        $0.values.keys.contains("kcal_consumed") && $0.values["kcal_consumed"]! == nil
    })
    #expect(nullRow.values["kcal_consumed"] == .some(nil))
}

@Test func dailyKpiRowNullColumnRoundTripsThroughEncodeDecode() throws {
    let json = Data(#"{"date":"2026-09-01","kcal_consumed":null,"tracked":true,"steps":8486}"#.utf8)
    let row = try JSON.decoder.decode(DailyKpiRow.self, from: json)
    #expect(row.values["kcal_consumed"] == .some(nil))
    #expect(row.values["tracked"] == 1)
    #expect(row.values["steps"] == 8486)

    let encoded = try JSON.encoder.encode(row)
    let encodedString = try #require(String(data: encoded, encoding: .utf8))
    #expect(encodedString.contains("\"kcal_consumed\":null"))

    let roundTripped = try JSON.decoder.decode(DailyKpiRow.self, from: encoded)
    #expect(roundTripped == row)
}

@Test func decodesMorning() throws {
    let m = try JSON.decoder.decode(MorningResponse.self, from: fixture("planning_morning"))
    #expect(m.carbWatchFloor > 0)
    #expect(m.hrvSeries.allSatisfy { $0.date.count == 10 })
}

@Test func decodesMorningVerdictRecoverySyncHealth() throws {
    _ = try JSON.decoder.decode(MorningVerdict.self, from: fixture("planning_morning_verdict"))
    let r = try JSON.decoder.decode(RecoveryReport.self, from: fixture("vitals_recovery"))
    #expect(!r.days.isEmpty)
    _ = try JSON.decoder.decode(SyncStatus.self, from: fixture("ingestion_status"))
    _ = try JSON.decoder.decode(HealthResponse.self, from: fixture("health"))
}

@Test(arguments: [
    (nil as String?, "—", "No verdict yet", VerdictTone.muted),
    ("GO — strength A", "GO", "strength A", VerdictTone.go),
    // Deliberate deviation from mobile/src/lib/verdict.ts, whose startsWith("RED") also catches
    // "REDUCED" — the design reserves amber for REDUCED (spec §4.6, 2026-09-13 ruling).
    ("REDUCED (sleep) — deload dose, not a day off", "REDUCED (sleep)", "deload dose, not a day off", VerdictTone.amber),
    ("RED — walk only", "RED", "walk only", VerdictTone.red),
])
func verdictPartsMatchesRN(input: String?, word: String, session: String, tone: VerdictTone) {
    let p = verdictParts(input)
    #expect(p.word == word); #expect(p.session == session); #expect(p.tone == tone)
}

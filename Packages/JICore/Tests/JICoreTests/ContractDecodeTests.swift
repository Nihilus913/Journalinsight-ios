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

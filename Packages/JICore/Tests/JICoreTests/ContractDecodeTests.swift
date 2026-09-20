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
    // "REDUCED" — the design reserves amber for REDUCED (mobile/src/theme/tokens.ts
    // verdict.reduced + plan L24, 2026-09-13 ruling).
    ("REDUCED (sleep) — deload dose, not a day off", "REDUCED (sleep)", "deload dose, not a day off", VerdictTone.amber),
    ("RED — walk only", "RED", "walk only", VerdictTone.red),
])
func verdictPartsMatchesRN(input: String?, word: String, session: String, tone: VerdictTone) {
    let p = verdictParts(input)
    #expect(p.word == word); #expect(p.session == session); #expect(p.tone == tone)
}

/// B-37-L1 (P-training) — `GET /api/v1/planning/workout-templates` (Wave Card B-37 ## Contract).
@Test func decodesWorkoutTemplates() throws {
    let templates = try JSON.decoder.decode([WorkoutTemplate].self, from: fixture("planning_workout_templates"))
    #expect(templates.count == 4)
    #expect(templates.map(\.name) == ["Zone 2 40 min", "Norwegian 4×4", "Zone 2 60 min", "Long Run Zone 2"])
    #expect(templates.allSatisfy { $0.activity == "running" && $0.location == .outdoor })
    #expect(templates.allSatisfy { $0.steps.allSatisfy { $0.hrHi <= 175 } })

    let norwegian = templates[1]
    #expect(norwegian.weekdays == [1, 5])
    #expect(norwegian.steps.map(\.purpose) == [.warmup, .work, .recovery, .cooldown])
    #expect(norwegian.steps[1].repeat == 4 && norwegian.steps[2].repeat == 4)
    #expect(norwegian.steps[1].hrLo == 160 && norwegian.steps[1].hrHi == 175)

    let longRun = templates[3]
    #expect(longRun.templateId == 4 && longRun.id == 4)
    #expect(longRun.weekdays == [6])
    #expect(longRun.steps.map(\.seconds) == [600, 4500, 300])
    #expect(longRun.updatedAt == "2026-09-21T00:00:00Z")
}

@Test func mockDataProviderServesFourWorkoutTemplates() async throws {
    let provider: any WorkoutTemplatesProviding = MockDataProvider()
    let templates = try await provider.workoutTemplates()
    #expect(templates.count == 4)
    #expect(templates.contains { $0.name == "Long Run Zone 2" })
}

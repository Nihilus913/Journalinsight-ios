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
    #expect(templates.map(\.name) == ["Long Run Zone 2", "Zone 2 40 min", "Norwegian 4×4", "Zone 2 60 min"])
    #expect(templates.allSatisfy { $0.activity == "running" && $0.location == .outdoor })
    #expect(templates.allSatisfy { $0.steps.allSatisfy { $0.hrHi <= 175 } })

    let norwegian = templates[2]
    #expect(norwegian.templateId == 3)
    #expect(norwegian.weekdays == [1, 5])
    #expect(norwegian.steps.map(\.purpose) == [.warmup, .work, .recovery, .cooldown])
    #expect(norwegian.steps[1].repeat == 4 && norwegian.steps[2].repeat == 4)
    #expect(norwegian.steps[1].hrLo == 160 && norwegian.steps[1].hrHi == 175)

    let longRun = templates[0]
    #expect(longRun.templateId == 1 && longRun.id == 1)
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

// MARK: - B-48 — digit-segment wire keys under `.convertFromSnakeCase`

/// B-48 guardrail #1 — the exact gap that let the bug ship: nothing ever decoded a literal
/// snake_case body and asserted the digit-segment fields came back NON-nil. `Codable` treats an
/// unmatched key on an `Optional` as absent, so the old spelling failed silently.
@Test func morningDecodesCarbs3dAvgFromTheLiteralSnakeCaseWireKey() throws {
    let json = Data(#"""
    {"today_activities": [], "verdict": "GO — Full Upper", "verdict_date": "2026-09-22",
     "experiment": null, "carbs_3d_avg": 165.5, "carb_watch_floor": 120, "hrv_series": []}
    """#.utf8)
    let m = try JSON.decoder.decode(MorningResponse.self, from: json)
    #expect(m.carbs3dAvg == 165.5)
}

@Test func gateAveragesDecodeEveryDigitSegmentFieldFromTheLiteralSnakeCaseWireKeys() throws {
    let json = Data(#"""
    {"avg_kcal_7d": 1583.1, "avg_protein_7d": 126.7, "avg_weight_kg": 104.2, "avg_rhr_bpm": 52.0,
     "sleep_score_7d": 76.2, "acwr": 0.94, "avg_body_battery": 61.0, "avg_kcal_burned_7d": 670.2,
     "avg_kcal_deficit_7d": 249.3, "est_weekly_weight_change_kg": -0.23, "trends": {}}
    """#.utf8)
    let a = try JSON.decoder.decode(GateAverages.self, from: json)
    #expect(a.avgKcal7d == 1583.1)
    #expect(a.avgProtein7d == 126.7)
    #expect(a.sleepScore7d == 76.2)
    #expect(a.avgKcalBurned7d == 670.2)
    #expect(a.avgKcalDeficit7d == 249.3)
    // The non-digit neighbours must not regress when an explicit `CodingKeys` list is introduced.
    #expect(a.avgWeightKg == 104.2)
    #expect(a.avgRhrBpm == 52.0)
    #expect(a.acwr == 0.94)
    #expect(a.avgBodyBattery == 61.0)
    #expect(a.estWeeklyWeightChangeKg == -0.23)
}

@Test func energyReportDecodesTheThree7dAveragesFromTheLiteralSnakeCaseWireKeys() throws {
    let json = Data(#"""
    {"days": [], "avg_deficit_raw_7d": 1165.9, "avg_deficit_corrected_7d": 164.8,
     "avg_deficit_pct_7d": 9.3, "tracking_days": 7, "compliant": true,
     "tdee_empirical": 2810.0, "goal_intake_kcal": 2200.0, "energy_avail": 31.4,
     "ea_warning": "low"}
    """#.utf8)
    let r = try JSON.decoder.decode(EnergyReport.self, from: json)
    #expect(r.avgDeficitRaw7d == 1165.9)
    #expect(r.avgDeficitCorrected7d == 164.8)
    #expect(r.avgDeficitPct7d == 9.3)
    #expect(r.tdeeEmpirical == 2810.0)
    #expect(r.goalIntakeKcal == 2200.0)
    #expect(r.energyAvail == 31.4)
    #expect(r.eaWarning == "low")
}

/// B-48 guardrail #2 — the shipped hub-contract fixtures themselves (not a hand-written body)
/// now have to produce non-nil digit-segment fields.
@Test func shippedHubContractFixturesCarryTheDigitSegmentFields() throws {
    let m = try JSON.decoder.decode(MorningResponse.self, from: fixture("planning_morning"))
    #expect(m.carbs3dAvg != nil)
    let a = try JSON.decoder.decode(GateResponse.self, from: fixture("planning_gate")).averages
    #expect(a.avgKcal7d != nil && a.avgProtein7d != nil && a.sleepScore7d != nil)
    #expect(a.avgKcalBurned7d != nil && a.avgKcalDeficit7d != nil)
    let e = try JSON.decoder.decode(EnergyReport.self, from: fixture("nutrition_energy"))
    #expect(e.avgDeficitRaw7d != nil && e.avgDeficitCorrected7d != nil && e.avgDeficitPct7d != nil)
}

/// B-48 guardrail #3 — the cache path. `JSON.encoder` (`.convertToSnakeCase`) re-mangles these
/// keys into its own spelling; the pair must still round-trip, so a cached response read back
/// after a cold start is not silently missing the same fields all over again. Table-driven over
/// every DTO that has a digit segment.
@Test func everyDigitSegmentDtoRoundTripsThroughTheEncoderDecoderPair() throws {
    let morning = try JSON.decoder.decode(MorningResponse.self, from: fixture("planning_morning"))
    #expect(try JSON.decoder.decode(MorningResponse.self, from: JSON.encoder.encode(morning)) == morning)

    let gate = try JSON.decoder.decode(GateResponse.self, from: fixture("planning_gate"))
    #expect(try JSON.decoder.decode(GateResponse.self, from: JSON.encoder.encode(gate)) == gate)

    let energy = try JSON.decoder.decode(EnergyReport.self, from: fixture("nutrition_energy"))
    #expect(try JSON.decoder.decode(EnergyReport.self, from: JSON.encoder.encode(energy)) == energy)
}

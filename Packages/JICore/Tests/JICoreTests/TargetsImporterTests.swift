import Foundation
import Testing
@testable import JICore

// W-TGT L1 — spec §5: import today's stored values verbatim; missing = nil; nothing seeded.

@Test func freshInstallImportsNothing() {
    let r = TargetsImporter.makeDocument(from: TargetsLegacySources())
    #expect(r.document == .empty)
    #expect(r.discarded.isEmpty)
}

@Test func goalsComeFromMacrosAndTheCachedHubGoals() {
    let macros = MacroGoals(kcal: KcalGoal(goalKcal: 1617, basis: .includesDeficit), proteinG: 155, carbsG: nil, fatG: 55)
    let hub = Goals(weight: WeightGoal(baseKg: 112, targetKg: 100, targetDate: "2027-03-01"),
                    strength: [StrengthGoal(exercise: "bench", targetKg: 80)], stepsDaily: 7000,
                    nutrition: NutritionGoal(kcalGoal: 1935, proteinG: 170))   // hub nutrition is NOT a source
    let d = TargetsImporter.makeDocument(from: TargetsLegacySources(macros: macros, hubGoals: hub)).document
    #expect(d.macroGoals == macros)
    #expect(d.goals.weight == WeightTarget(baseKg: 112, targetKg: 100, targetDate: "2027-03-01"))
    #expect(d.goals.stepsDaily == 7000)
    #expect(d.goals.strength == [StrengthGoal(exercise: "bench", targetKg: 80)])
    #expect(d.goals.sleepH == nil)   // D2: never seeded
}

@Test func limitsAndPresetComeFromGateSettingsVerbatim() {
    let zones = HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176])
    let gate = LegacyGateSettings(preset: "cautious", hrCapBpm: 175, avoidZone5: true, zones: zones, hrCapConfirmedOn: "2026-09-24")
    let d = TargetsImporter.makeDocument(from: TargetsLegacySources(gateSettings: gate)).document
    #expect(d.limits == TargetLimits(hrCapBpm: 175, hrCapConfirmedOn: "2026-09-24", zones: zones, avoidZone5: true))
    #expect(d.rules[.hrvLowNights] == 1)
}

@Test func noCapStaysNoCap() {
    let gate = LegacyGateSettings(preset: "push", hrCapBpm: nil, avoidZone5: false, zones: nil, hrCapConfirmedOn: "2026-09-25")
    let d = TargetsImporter.makeDocument(from: TargetsLegacySources(gateSettings: gate)).document
    #expect(d.limits.hrCapBpm == nil && d.limits.zones == nil)
    #expect(d.rules[.hrvLowNights] == 3)
}

@Test func legacyGateSettingsBlobDecodesLikeGateSettings() throws {
    let json = #"{"preset":"balanced","hr_cap_bpm":175,"avoid_zone5":true,"zones":{"anchor":"maxHr","anchor_bpm":198,"floors_bpm":[97,117,139,160,176]},"hr_cap_confirmed_on":null}"#
    let g = try JSON.decoder.decode(LegacyGateSettings.self, from: Data(json.utf8))
    #expect(g.preset == "balanced" && g.hrCapBpm == 175 && g.avoidZone5 && g.zones?.floorsBpm.count == 5 && g.hrCapConfirmedOn == nil)
}

@Test func morningOverridesBecomeRulesOnlyWhenOverridden() {
    let d = TargetsImporter.makeDocument(from: TargetsLegacySources(
        morningOverrides: ["RESP_DELTA_AMBER": 2.5, "MIN_SLEEP_H": 5.5]
    )).document
    #expect(d.rules[.respDeltaAmber] == 2.5)
    #expect(d.rules[.intervalMinSleep] == 5.5)
    #expect(d.rules[.carbThreeDayFloor] == nil)   // not overridden = recommended
}

@Test func kpiTargetRowsBecomeRulesWithTheirCurrentNumbers() {
    let rows = [
        KpiTarget(targetId: 1, metric: "acwr", operator: ">", threshold: 1.35),
        KpiTarget(targetId: 2, metric: "avg_kcal_7d", operator: "<", threshold: 1600),
        KpiTarget(targetId: 3, metric: "avg_protein_7d", operator: "<", threshold: 130),
        KpiTarget(targetId: 4, metric: "sleep_score_7d", operator: "<", threshold: 55),
        KpiTarget(targetId: 5, metric: "acwr", operator: "<", threshold: 0.8),
        KpiTarget(targetId: 6, metric: "acwr", operator: "between", threshold: 0.8, thresholdHi: 1.3),
        KpiTarget(targetId: 7, metric: "mystery", operator: "<", threshold: 1),
    ]
    let r = TargetsImporter.makeDocument(from: TargetsLegacySources(kpiTargets: rows))
    let d = r.document
    #expect(d.rules[.loadOver] == 1.35)
    #expect(d.rules[.weekKcalFloor] == 1600)
    #expect(d.rules[.weekProteinFloor] == 130)
    #expect(d.rules[.weekSleepScoreFloor] == 55)
    #expect(d.rules[.loadUnder] == 0.8)
    #expect(d.rules[.loadBandLow] == 0.8 && d.rules[.loadBandHigh] == 1.3)
    #expect(r.discarded.contains { $0.contains("mystery") })
}

/// §5.3: hidden R3 overrides and the preview-only kpi_rules are read once and discarded; the GOAL
/// (the shown number) wins; every discarded value is logged.
@Test func hiddenOverridesAreDiscardedAndLogged() {
    let macros = MacroGoals(kcal: KcalGoal(goalKcal: 1617, basis: .includesDeficit))
    let r = TargetsImporter.makeDocument(from: TargetsLegacySources(
        macros: macros,
        morningOverrides: ["KCAL_TARGET": 1800, "STEP_TARGET": 15000, "TARGET_WEIGHT": 95, "PROTEIN_TARGET": 172],
        kpiRuleOverrides: ["acwr|>": LegacyKpiRuleOverride(threshold: 1.5, thresholdHi: nil)]
    ))
    #expect(r.document.goal(.kcal) == 1617)
    #expect(r.document.goal(.steps) == nil)       // a hidden override never becomes a goal
    #expect(r.document.goal(.weight) == nil)
    #expect(r.document.goal(.protein) == nil)
    #expect(r.document.rules[.loadOver] == nil)   // preview-only copy is not a rule
    #expect(r.discarded.count == 5)
    #expect(r.discarded.contains { $0.contains("KCAL_TARGET") && $0.contains("1800") })
}

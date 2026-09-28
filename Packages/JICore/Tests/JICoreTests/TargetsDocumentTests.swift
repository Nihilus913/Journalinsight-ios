import Foundation
import Testing
@testable import JICore

// W-TGT L1 — the frozen §3 document. Every number below is a test value "typed by a user";
// JI ships none of them (only Rule recommendations, which are the gate's current constants).

private let typed = TargetsDocument(
    goals: TargetGoals(
        weight: WeightTarget(baseKg: 112, targetKg: 100, targetDate: "2027-03-01"),
        kcal: KcalGoal(goalKcal: 2100, basis: .subtractDeficit(.deficit(kcalPerDay: 500))),
        proteinG: 155, carbsG: nil, fatG: 60, stepsDaily: 7000, sleepH: nil,
        strength: [StrengthGoal(exercise: "bench", targetKg: 80)]
    ),
    limits: TargetLimits(hrCapBpm: 175, hrCapConfirmedOn: "2026-09-24",
                         zones: HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176]),
                         avoidZone5: true),
    rules: TargetRules([.hrvLowNights: 2, .weekKcalFloor: 1600, .loadBandLow: 0.8, .loadBandHigh: 1.3])
)

@Test func emptyDocumentHasNoNumbers() {
    let e = TargetsDocument.empty
    for m in GoalMetric.allCases { #expect(e.goal(m) == nil) }
    for m in LimitMetric.allCases { #expect(e.limit(m) == nil) }
    for r in RuleMetric.allCases { #expect(e.rules[r] == nil) }
    #expect(e.limits.avoidZone5 == false)
    #expect(e.goals.strength.isEmpty)
    #expect(e.workoutLimits == .none)
}

@Test func goalAccessorsReadTheOneNumberPerMetric() {
    #expect(typed.goal(.kcal) == 1600)       // goal − deficit, the number every surface shows
    #expect(typed.goal(.protein) == 155)
    #expect(typed.goal(.carbs) == nil)
    #expect(typed.goal(.fat) == 60)
    #expect(typed.goal(.steps) == 7000)
    #expect(typed.goal(.weight) == 100)
    #expect(typed.goal(.sleep) == nil)       // D2: nil until the user types it
}

@Test func limitAccessorsAndWorkoutLimits() {
    #expect(typed.limit(.hrCap) == 175)
    #expect(typed.limit(.zone5Floor) == 176)
    #expect(typed.workoutLimits == WorkoutHrLimits(capBpm: 175, zone5FloorBpm: 176))
    var noAvoid = typed; noAvoid.limits.avoidZone5 = false
    #expect(noAvoid.limit(.zone5Floor) == nil)
}

@Test func ruleFallsBackToRecommendedAndSaysSo() {
    #expect(typed.rule(.weekKcalFloor) == 1600)
    #expect(typed.isRecommended(.weekKcalFloor))              // stored value == recommended
    #expect(typed.rule(.weekProteinFloor) == RuleMetric.weekProteinFloor.recommended)
    #expect(typed.isRecommended(.weekProteinFloor))           // nil = recommended
    var changed = typed; changed.rules[.weekProteinFloor] = 140
    #expect(!changed.isRecommended(.weekProteinFloor))
    changed.rules[.weekProteinFloor] = nil                    // Reset
    #expect(changed.isRecommended(.weekProteinFloor))
}

/// The recommended values are today's gate constants (hub `plan.kpi_target` seeds 003/004 and
/// `morning_go` constants), never a goal and never a limit.
@Test func recommendedRulesAreTodaysConstants() {
    let expected: [RuleMetric: Double] = [
        .hrvLowNights: 2, .respDeltaAmber: 2.0, .carbThreeDayFloor: 120, .intervalMinSleep: 6.0,
        .loadOver: 1.30, .loadUnder: 0.80, .loadBandLow: 0.80, .loadBandHigh: 1.30,
        .weekKcalFloor: 1600, .weekProteinFloor: 130, .weekSleepScoreFloor: 55,
    ]
    for r in RuleMetric.allCases { #expect(r.recommended == expected[r], "\(r)") }
}

@Test func macroGoalsBridgeRoundTrips() {
    var d = TargetsDocument.empty
    let m = MacroGoals(kcal: KcalGoal(goalKcal: 1617, basis: .includesDeficit), proteinG: 155, carbsG: 160, fatG: nil)
    d.macroGoals = m
    #expect(d.macroGoals == m)
    #expect(d.goal(.kcal) == 1617)
    #expect(TargetsDocument.empty.macroGoals == .unset)
}

@Test func prefStoreEncodingRoundTrips() throws {
    let data = try JSON.encoder.encode(typed)
    #expect(try JSON.decoder.decode(TargetsDocument.self, from: data) == typed)
}

@Test func outboxPlainEncodingRoundTrips() throws {
    let data = try JSONEncoder().encode(typed)
    #expect(try JSONDecoder().decode(TargetsDocument.self, from: data) == typed)
}

/// The frozen wire shape (spec §3; the hub's `PUT /planning/targets` body): snake_case keys,
/// every Goal/Limit/Rule key present, unset = JSON null.
@Test func wireBodyIsTheFrozenShape() throws {
    let data = try JSONEncoder().encode(try typed.wireBody())
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(obj.keys) == ["version", "goals", "limits", "rules"])
    #expect(obj["version"] as? Int == 1)
    let goals = try #require(obj["goals"] as? [String: Any])
    #expect(Set(goals.keys) == ["weight", "kcal", "protein_g", "carbs_g", "fat_g", "steps_daily", "sleep_h", "strength"])
    #expect(goals["carbs_g"] is NSNull)
    #expect(goals["sleep_h"] is NSNull)
    #expect(goals["steps_daily"] as? Int == 7000)
    let kcal = try #require(goals["kcal"] as? [String: Any])
    #expect(kcal["goal_kcal"] as? Double == 2100)
    #expect(kcal["basis"] as? String == "subtract_deficit")
    #expect(kcal["deficit_kcal_per_day"] as? Double == 500)
    #expect(kcal["weekly_loss_kg"] is NSNull)
    #expect(kcal["target_kcal"] as? Double == 1600)
    let weight = try #require(goals["weight"] as? [String: Any])
    #expect(weight["target_kg"] as? Double == 100 && weight["base_kg"] as? Double == 112)
    #expect(weight["target_date"] as? String == "2027-03-01")
    let strength = try #require(goals["strength"] as? [[String: Any]])
    #expect(strength.first?["exercise"] as? String == "bench" && strength.first?["target_kg"] as? Double == 80)

    let limits = try #require(obj["limits"] as? [String: Any])
    #expect(Set(limits.keys) == ["hr_cap_bpm", "hr_cap_confirmed_on", "zones", "avoid_zone5"])
    #expect(limits["hr_cap_bpm"] as? Int == 175)
    #expect(limits["avoid_zone5"] as? Bool == true)
    let zones = try #require(limits["zones"] as? [String: Any])
    #expect(zones["floors_bpm"] as? [Int] == [97, 117, 139, 160, 176])
    #expect(zones["anchor"] as? String == "maxHr" && zones["anchor_bpm"] as? Int == 198)

    let rules = try #require(obj["rules"] as? [String: Any])
    #expect(Set(rules.keys) == Set(RuleMetric.allCases.map(\.wireKey)))
    #expect(rules["hrv_low_nights"] as? Int == 2)
    #expect(rules["week_kcal_floor"] as? Double == 1600)
    #expect(rules["resp_delta_amber"] is NSNull)
    #expect(rules["load_band_high"] as? Double == 1.3)
}

@Test func wireKeysAreSnakeCase() {
    #expect(RuleMetric.allCases.map(\.wireKey) == [
        "hrv_low_nights", "resp_delta_amber", "carb_three_day_floor", "interval_min_sleep",
        "load_over", "load_under", "load_band_low", "load_band_high",
        "week_kcal_floor", "week_protein_floor", "week_sleep_score_floor",
    ])
}

/// The hub's answer decodes with `JSON.decoder` (HubClient), including unknown extra keys.
@Test func hubResponseDecodesTolerantly() throws {
    let json = """
    {"version":1,"updated_at":"2026-09-28T05:00:00Z",
     "goals":{"weight":null,"kcal":{"goal_kcal":1617,"basis":"includes_deficit","deficit_kcal_per_day":null,"weekly_loss_kg":null,"target_kcal":1617},
              "protein_g":155,"carbs_g":null,"fat_g":null,"steps_daily":null,"sleep_h":7,"strength":[]},
     "limits":{"hr_cap_bpm":null,"hr_cap_confirmed_on":null,"zones":null,"avoid_zone5":false},
     "rules":{"hrv_low_nights":3,"week_kcal_floor":1600,"future_rule":9}}
    """
    let d = try JSON.decoder.decode(TargetsDocument.self, from: Data(json.utf8))
    #expect(d.goal(.kcal) == 1617)
    #expect(d.goals.kcal?.basis == .includesDeficit)
    #expect(d.goal(.sleep) == 7)
    #expect(d.limit(.hrCap) == nil)
    #expect(d.rules[.hrvLowNights] == 3)
    #expect(d.rules[.weekKcalFloor] == 1600)
    #expect(d.rules[.loadOver] == nil)
}

/// A damaged field never takes the rest of the document with it, and never becomes a number.
@Test func damagedFieldsDecodeAsNil() throws {
    let json = """
    {"goals":{"protein_g":"lots","fat_g":60,"kcal":{"goal_kcal":1600,"basis":"??"}},
     "limits":{"hr_cap_bpm":"x","zones":{"anchor":"maxHr","anchor_bpm":198,"floors_bpm":[1,2]}},
     "rules":{"week_kcal_floor":"x","load_over":1.4}}
    """
    let d = try JSON.decoder.decode(TargetsDocument.self, from: Data(json.utf8))
    #expect(d.goals.proteinG == nil && d.goals.fatG == 60)
    #expect(d.goals.kcal == nil)
    #expect(d.limits.hrCapBpm == nil && d.limits.zones == nil)
    #expect(d.rules[.weekKcalFloor] == nil && d.rules[.loadOver] == 1.4)
    #expect(d.version == TargetsDocument.currentVersion)
}

@Test func weeklyLossBasisRoundTripsOnTheWire() throws {
    var d = TargetsDocument.empty
    d.goals.kcal = KcalGoal(goalKcal: 2300, basis: .subtractDeficit(.weeklyLoss(kgPerWeek: 0.5)))
    let data = try JSONEncoder().encode(try d.wireBody())
    let back = try JSON.decoder.decode(TargetsDocument.self, from: data)
    #expect(back.goals.kcal == d.goals.kcal)
}

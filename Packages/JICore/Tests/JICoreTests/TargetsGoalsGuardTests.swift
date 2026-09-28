import Foundation
import Testing
@testable import JICore

// W-FIX8 T-1 — the goals-empty guard's document side: what "no goals" means, the
// `clear_all_goals` wire flag, and "hub wins over empty local".

private let hubDoc: TargetsDocument = {
    var d = TargetsDocument(
        goals: TargetGoals(weight: WeightTarget(baseKg: 80.2, targetKg: 75, targetDate: "2026-10-31"),
                           kcal: KcalGoal(goalKcal: 1935, basis: .includesDeficit), proteinG: 184.9,
                           stepsDaily: 15000, strength: [StrengthGoal(exercise: "bench", targetKg: 100)]),
        limits: TargetLimits(hrCapBpm: 175, zones: HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176]),
                             avoidZone5: true))
    for r in RuleMetric.allCases { d.rules[r] = r.recommended }   // GET answers every rule resolved
    d.rules[.weekKcalFloor] = 1500
    return d
}()

private func object(_ v: JSONValue) -> [String: JSONValue]? { if case .object(let o) = v { o } else { nil } }

@Test func goalsIsEmptyOnlyWithNoGoalAtAll() {
    #expect(TargetGoals().isEmpty)
    #expect(TargetGoals(weight: WeightTarget()).isEmpty)                    // an all-nil weight is none
    #expect(!TargetGoals(weight: WeightTarget(targetKg: 75)).isEmpty)
    #expect(!TargetGoals(proteinG: 150).isEmpty)
    #expect(!TargetGoals(sleepH: 7).isEmpty)
    #expect(!TargetGoals(strength: [StrengthGoal(exercise: "row", targetKg: 90)]).isEmpty)
    #expect(TargetLimits().isEmpty && !TargetLimits(avoidZone5: true).isEmpty && !TargetLimits(hrCapBpm: 170).isEmpty)
}

@Test func clearAllGoalsIsOnTheWireOnlyWhenSet() throws {
    let plain = try #require(object(try TargetsDocument.empty.wireBody()))
    #expect(plain["clear_all_goals"] == nil)
    var clear = TargetsDocument.empty; clear.clearAllGoals = true
    let body = try #require(object(try clear.wireBody()))
    #expect(body["clear_all_goals"] == .bool(true))
    // The outbox round-trip keeps the intent.
    let back = try JSONDecoder().decode(TargetsDocument.self, from: JSONEncoder().encode(clear))
    #expect(back.clearAllGoals)
}

@Test func emptyLocalAdoptsTheHubDocument() {
    let adopted = TargetsDocument.empty.adoptingHub(hubDoc)
    #expect(adopted.goals == hubDoc.goals)
    #expect(adopted.limits == hubDoc.limits)
    #expect(adopted.rules[.weekKcalFloor] == 1500)
    #expect(adopted.rules[.loadOver] == nil)          // the recommended number stays "recommended"
    #expect(!adopted.clearAllGoals)
}

@Test func adoptingNeverOverwritesWhatThePhoneHolds() {
    var local = TargetsDocument.empty
    local.limits.hrCapBpm = 170
    local.rules[.weekKcalFloor] = 1700
    let adopted = local.adoptingHub(hubDoc)
    #expect(adopted.goals == hubDoc.goals)            // goals were empty → hub's
    #expect(adopted.limits.hrCapBpm == 170 && adopted.limits.zones == nil)
    #expect(adopted.rules[.weekKcalFloor] == 1700)
    var withGoal = TargetsDocument.empty; withGoal.goals.proteinG = 140
    #expect(withGoal.adoptingHub(hubDoc).goals == withGoal.goals)
}

import Foundation
import Testing
@testable import JICore

/// Every number below is a test value typed "by a user". JI ships none of them.
private let sample = MacroGoals(
    kcal: KcalGoal(goalKcal: 2300, basis: .subtractDeficit(.deficit(kcalPerDay: 500))),
    proteinG: 160, carbsG: 140, fatG: 50
)

@Test func goalsStartUnsetWithNoNumbers() {
    let u = MacroGoals.unset
    #expect(u.kcal == nil)
    #expect(u.proteinG == nil && u.carbsG == nil && u.fatG == nil)
    #expect(u.isUnset)
    #expect(u.targetKcal == nil)
    for id in [KpiMetricId.kcal, .protein, .carbs, .fat] { #expect(u.goal(for: id) == nil) }
}

/// The goal already includes the deficit: the target IS the goal. Never subtract again.
@Test func includesDeficitTargetIsTheGoal() {
    let k = KcalGoal(goalKcal: 1600, basis: .includesDeficit)
    #expect(k.deficitKcalPerDay == 0)
    #expect(k.targetKcal == 1600)
}

@Test func subtractDeficitTargetIsGoalMinusDeficit() {
    #expect(KcalGoal(goalKcal: 2100, basis: .subtractDeficit(.deficit(kcalPerDay: 500))).targetKcal == 1600)
}

@Test func weeklyLossConvertsAt7700PerKg() {
    let k = KcalGoal(goalKcal: 2300, basis: .subtractDeficit(.weeklyLoss(kgPerWeek: 0.5)))
    #expect(k.deficitKcalPerDay == 550)
    #expect(k.targetKcal == 1750)
}

@Test func negativeDeficitInputsClampToZero() {
    #expect(KcalGoal(goalKcal: 2000, basis: .subtractDeficit(.deficit(kcalPerDay: -200))).targetKcal == 2000)
    #expect(KcalGoal(goalKcal: 2000, basis: .subtractDeficit(.weeklyLoss(kgPerWeek: -1))).targetKcal == 2000)
}

@Test func validityNeedsAPositiveGoalAndTarget() {
    #expect(KcalGoal(goalKcal: 1600, basis: .includesDeficit).isValid)
    #expect(!KcalGoal(goalKcal: 0, basis: .includesDeficit).isValid)
    #expect(!KcalGoal(goalKcal: 400, basis: .subtractDeficit(.deficit(kcalPerDay: 500))).isValid)
}

@Test func goalForKpiMapsOnlyTheFourNutritionKpisAndOnlyWhenSet() {
    #expect(sample.goal(for: .kcal) == 1800)          // the target, not the typed goal
    #expect(sample.goal(for: .protein) == 160)
    #expect(sample.goal(for: .carbs) == 140)
    #expect(sample.goal(for: .fat) == 50)
    #expect(sample.goal(for: .hrv) == nil)
    let partial = MacroGoals(proteinG: 160)
    #expect(partial.goal(for: .protein) == 160)
    #expect(partial.goal(for: .kcal) == nil)
    #expect(partial.goal(for: .carbs) == nil)
    #expect(!partial.isUnset)
}

/// PrefStore writes with `JSON.encoder` (snake_case). The stored keys must survive the decoder's
/// snake→camel pass (B-48 trap). Unset fields are omitted, never written as 0.
@Test func prefStoreWireShapeRoundTrips() throws {
    let data = try JSON.encoder.encode(sample)
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(obj.keys) == ["kcal", "protein_g", "carbs_g", "fat_g"])
    let kcal = try #require(obj["kcal"] as? [String: Any])
    #expect(Set(kcal.keys) == ["goal_kcal", "basis"])
    #expect(try JSON.decoder.decode(MacroGoals.self, from: data) == sample)

    let includes = MacroGoals(kcal: KcalGoal(goalKcal: 1600, basis: .includesDeficit))
    #expect(try JSON.decoder.decode(MacroGoals.self, from: JSON.encoder.encode(includes)) == includes)

    let unsetData = try JSON.encoder.encode(MacroGoals.unset)
    let unsetObj = try #require(try JSONSerialization.jsonObject(with: unsetData) as? [String: Any])
    #expect(unsetObj.isEmpty)
    #expect(try JSON.decoder.decode(MacroGoals.self, from: unsetData) == .unset)
}

@Test func copyIsVerbatim() {
    #expect(MacroGoals.trackerDisclaimer == "Align your food tracker's kcal goal with this.")
    #expect(MacroGoals.bandSettleNote == "The band settles after a full week of Apple Health data.")
    #expect(MacroGoals.setGoalCopy == "Set your goal")
}

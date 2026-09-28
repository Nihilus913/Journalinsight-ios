import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-TGT fixer round 2 (verifier rows R1–R3). Test values only.

// MARK: - R1 kcal editor never saves a target at or below zero

private func kcalDraft(goal: String, deficit: String, weekly: Bool = false) -> TargetEditDraft {
    var d = TargetEditDraft(subject: .goal(.kcal), document: .empty)
    d.goalText = goal; d.deficitText = deficit; d.deficitIsWeeklyLoss = weekly
    return d
}

@Test func aDeficitBiggerThanTheGoalIsRefusedWithAReason() {
    let d = kcalDraft(goal: "2,117", deficit: "400,500")
    #expect(d.validationMessage != nil)
    if case .failure(.invalid(let why)) = d.applied(to: .empty) { #expect(!why.isEmpty) } else { Issue.record("saved a negative target") }
}

@Test func aDeficitEqualToTheGoalIsRefused() {
    #expect(kcalDraft(goal: "2000", deficit: "2000").validationMessage != nil)
}

@Test func aWeeklyLossThatEatsTheGoalIsRefused() {
    #expect(kcalDraft(goal: "2000", deficit: "5", weekly: true).validationMessage != nil)
}

@Test func aNormalDeficitSavesItsTarget() {
    let d = kcalDraft(goal: "2117", deficit: "500")
    #expect(d.validationMessage == nil)
    guard case .success(let doc) = d.applied(to: .empty) else { Issue.record("refused"); return }
    #expect(doc.goals.kcal?.targetKcal == 1617)
}

@Test func aGoalAtOrBelowZeroIsRefused() {
    #expect(kcalDraft(goal: "-5", deficit: "").validationMessage != nil)
    var p = TargetEditDraft(subject: .goal(.protein), document: .empty)
    p.goalText = "0"
    #expect(p.validationMessage != nil)
    p.goalText = ""
    #expect(p.validationMessage == nil)   // blank = no goal
}

@Test func aNegativeDeficitIsRefused() {
    #expect(kcalDraft(goal: "2000", deficit: "-100").validationMessage != nil)
}

// MARK: - R2 labels match their metric

@Test func theSleepHoursGoalHasNoScoreNormal() {
    // The sleep KPI is the 0–100 score; the goal is hours. No hours history = no normal row.
    #expect(targetsNormalMetric(.goal(.sleep)) == nil)
    #expect(targetsNormalMetric(.goal(.kcal)) == .kcal)
}

@Test func theSleepScoreSquareNeverCarriesTheHoursGoal() {
    var d = TargetsDocument.empty
    d.goals.sleepH = 7.5
    #expect(kpiListGoalCaption(.sleep, value: 94, targets: d) == nil)
    #expect(kpiListGoalCaption(.steps, value: 9000, targets: d) == "no goal")
}

@Test func theKpiCardNamesTheSleepScoreNormal() {
    #expect(kpiTargetsNormalPrefix(.sleep) == "score ")
    #expect(kpiTargetsNormalPrefix(.kcal) == "")
}

@Test func moreGoalsCountsGoalsWhenThereIsNoWeightGoal() {
    #expect(moreGoalsValue(currentKg: nil, targetKg: nil, otherGoals: 2).text == "2 goals set")
    #expect(moreGoalsValue(currentKg: nil, targetKg: nil, otherGoals: 1).text == "1 goal set")
    #expect(moreGoalsValue(currentKg: nil, targetKg: nil, otherGoals: 0).text == "— No goal set")
    let g = Goals(weight: WeightGoal(baseKg: nil, targetKg: .nan, targetDate: nil), strength: [], stepsDaily: 7000,
                  nutrition: NutritionGoal(kcalGoal: 1617, proteinG: nil, carbsG: nil, fatG: nil))
    #expect(goalsSetCount(g) == 2)
    #expect(goalsSetCount(nil) == 0)
}

// MARK: - R3 copy: "goal", never "target", grouped numbers

@Test func goalsScreenSaysGoalAndGroupsNumbers() {
    let g = Goals(weight: WeightGoal(baseKg: nil, targetKg: 75, targetDate: nil), strength: [], stepsDaily: 15000,
                  nutrition: NutritionGoal(kcalGoal: nil, proteinG: nil, carbsG: nil, fatG: nil))
    let rows = GoalsBoard.targets(goals: g, macros: MacroGoals(kcal: KcalGoal(goalKcal: 1617, basis: .includesDeficit), proteinG: 155),
                                  yesterdayKcal: 1619, yesterdayProteinG: 127, yesterdaySteps: 12345)
    #expect(rows[0].subtitle == "goal 1,617 a day")
    #expect(rows[0].value == "1,619 kcal")
    #expect(rows.last?.subtitle == "goal 15,000 a day")
    #expect(rows.last?.value == "12,345")
    for r in rows {
        #expect(!r.subtitle.lowercased().contains("target"))
        #expect(!(r.status ?? "").lowercased().contains("target"))
    }
    #expect(!goalsYoursCaption.lowercased().contains("target"))
    #expect(!goalsNoHeroText.lowercased().contains("target"))
}

@Test func moreNutritionGroupsItsNumbers() {
    #expect(moreNutritionValue(consumedKcal: 1467.4, goalKcal: 1617).text == "1,467 / 1,617 kcal")
}

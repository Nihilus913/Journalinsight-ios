import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-FIX2 BUG-41 (board 3/05): More → Goals = one active weight-goal hero, supporting targets and
// "Edit targets" → GoalsSetup — never the legacy ad-hoc form.
@Suite struct GoalsBoardTests {
    let goals = Goals(weight: WeightGoal(baseKg: 80.2, targetKg: 75.0, targetDate: "2026-10-31"),
                      strength: [StrengthGoal(exercise: "Bench press", targetKg: 50)],
                      stepsDaily: 15000, nutrition: NutritionGoal(kcalGoal: 1617, proteinG: 155))
    let today = "2026-09-25"
    /// B-73: the user's own goals (PrefStore `goals.macros`) — the only source of the kcal/protein rows.
    let userMacros = MacroGoals(kcal: KcalGoal(goalKcal: 1617, basis: .includesDeficit), proteinG: 155)

    @Test func heroShowsTheActiveWeightGoalStartToTarget() throws {
        let hero = try #require(GoalsBoard.hero(goals: goals, latestKg: 79.5, avgDeficit7d: 598, trackingDays: 7, today: today))
        #expect(hero.kind == "ACTIVE · REDUCE WEIGHT")
        #expect(hero.byLine == "by 31 Oct")
        #expect(hero.startText == "80.2 kg")
        #expect(hero.targetText == "75.0")
    }

    @Test func paceProjectsTheLatestWeightAtTheCurrentDeficit() throws {
        let hero = try #require(GoalsBoard.hero(goals: goals, latestKg: 79.5, avgDeficit7d: 598, trackingDays: 7, today: today))
        // 36 days × 598 kcal / 7700 ≈ 2.8 kg → ≈ 76.7 kg; target 75.0 → behind.
        #expect(hero.paceStatus == "Behind pace")
        #expect(hero.paceLine.contains("\u{2212}598 kcal a day"))
        #expect(hero.paceLine.contains("76.7 kg on 31 Oct"))
        #expect(hero.paceLine.contains("Hitting 75.0 needs about"))
    }

    @Test func missingPaceInputsSayNoDataNeverAnInventedNumber() throws {
        let hero = try #require(GoalsBoard.hero(goals: goals, latestKg: nil, avgDeficit7d: 598, trackingDays: 7, today: today))
        #expect(hero.paceStatus == nil)
        #expect(hero.paceLine.hasPrefix("Pace —"))
        let few = try #require(GoalsBoard.hero(goals: goals, latestKg: 79.5, avgDeficit7d: 598, trackingDays: 2, today: today))
        #expect(few.paceStatus == nil)
    }

    @Test func noGoalsDocumentMeansNoHero() {
        #expect(GoalsBoard.hero(goals: nil, latestKg: 79.5, avgDeficit7d: 598, trackingDays: 7, today: today) == nil)
    }

    @Test func supportingTargetsAreCaloriesProteinTrainingStrengthSteps() {
        let rows = GoalsBoard.targets(goals: goals, macros: userMacros, yesterdayKcal: 1619, yesterdayProteinG: 127, yesterdaySteps: nil)
        #expect(rows.map(\.title) == ["Calories", "Protein", goalsTrainingPlanTitle, "Bench press", "Daily steps"])
        #expect(rows[0].subtitle == "goal 1617 a day")
        #expect(rows[0].value == "1619 kcal")
        #expect(rows[0].status == "On target")
        #expect(rows[1].value == "127 g")
        #expect(rows[1].status == "Below target")
        #expect(rows[2].value == "— of 4")
        #expect(rows[3].value == "50.0 kg")
        #expect(rows[4].subtitle == "target 15000")
        #expect(rows[4].value == "— No data")
        #expect(rows[4].status == nil)
    }

    // W-B57-W2 fixer GOALS-HUB-SEED: the hub document's seeded nutrition (184.9 g / 1935 kcal) is
    // never a Goals target. Unset user goals = "Set your goal", no status, never a hub number.
    @Test func calorieAndProteinRowsIgnoreTheHubSeedWhileTheUserGoalIsUnset() {
        let seeded = Goals(weight: goals.weight, strength: goals.strength, stepsDaily: 15000,
                           nutrition: NutritionGoal(kcalGoal: 1935, proteinG: 184.9))
        let rows = GoalsBoard.targets(goals: seeded, macros: .unset, yesterdayKcal: 1619, yesterdayProteinG: 127, yesterdaySteps: nil)
        #expect(rows[0].subtitle == MacroGoals.setGoalCopy)
        #expect(rows[0].status == nil)
        #expect(rows[1].subtitle == MacroGoals.setGoalCopy)
        #expect(rows[1].status == nil)
        #expect(!rows.contains { $0.subtitle.contains("185") || $0.subtitle.contains("1935") })
        let none = GoalsBoard.targets(goals: seeded, macros: nil, yesterdayKcal: 1619, yesterdayProteinG: 127, yesterdaySteps: nil)
        #expect(none[1].subtitle == MacroGoals.setGoalCopy)
    }

    @Test func calorieRowUsesTheUserTargetNotTheTypedGoalWhenJISubtractsADeficit() {
        let m = MacroGoals(kcal: KcalGoal(goalKcal: 2400, basis: .subtractDeficit(.deficit(kcalPerDay: 500))), proteinG: 160)
        let rows = GoalsBoard.targets(goals: goals, macros: m, yesterdayKcal: 1900, yesterdayProteinG: 160, yesterdaySteps: nil)
        #expect(rows[0].subtitle == "goal 1900 a day")
        #expect(rows[0].status == "On target")
        #expect(rows[1].subtitle == "goal 160 g a day")
    }

    // GOALS-HUB-SEED: Goals setup's "Current targets" Kcal row is the user's target, never the hub's 1935.
    @Test func mirrorKcalRowIsTheUserTargetNeverTheHubSeed() {
        #expect(goalTargetsMirrorKcalText(macros: nil) == "—")
        #expect(goalTargetsMirrorKcalText(macros: .unset) == "—")
        #expect(goalTargetsMirrorKcalText(macros: userMacros) == "1617")
    }
}

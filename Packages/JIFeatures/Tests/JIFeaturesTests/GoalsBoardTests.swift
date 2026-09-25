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
        let rows = GoalsBoard.targets(goals: goals, yesterdayKcal: 1619, yesterdayProteinG: 127, yesterdaySteps: nil)
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
}

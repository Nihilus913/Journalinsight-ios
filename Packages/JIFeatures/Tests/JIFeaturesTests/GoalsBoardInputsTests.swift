import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX12 F12-1 (H2-23): More › Goals shows each metric's LATEST reading with its date — never
// yesterday's value only (blank the moment yesterday has no row).
@Suite struct GoalsBoardInputsTests {
    let today = "2026-10-03"
    let goals = Goals(weight: WeightGoal(baseKg: 80.2, targetKg: 75.0, targetDate: "2026-10-31"),
                      strength: [], stepsDaily: 15000, nutrition: NutritionGoal())

    @Test func weighInFourDaysAgoIsShownWithItsDate() {
        let rows = [DailyKpiRow(date: "2026-09-29", values: ["weight_kg": 79.5, "steps": 9000]),
                    DailyKpiRow(date: "2026-10-02", values: ["weight_kg": nil, "steps": 12000])]
        let input = GoalsBoardInputs.build(goals: goals, dailyRows: rows, gateAverages: nil, nutrition: [], energyDays: [],
                                           avgDeficit7d: nil, trackingDays: 0, today: today)
        #expect(input.latestKg == 79.5)
        #expect(input.latestWeightText == "79.5 kg · 29 Sep")
    }

    @Test func supportingRowsReadTheNewestCompleteDayNotOnlyYesterday() {
        // Nothing logged yesterday (10-02): the 30 Sep day is the latest reading, dated.
        let nutrition = [NutritionDailyRow(date: "2026-09-30", kcalConsumed: 1619, proteinG: 127),
                         NutritionDailyRow(date: "2026-10-02"),
                         NutritionDailyRow(date: "2026-10-03", kcalConsumed: 400, proteinG: 20)]   // today = partial
        let rows = [DailyKpiRow(date: "2026-10-01", values: ["steps": 12000]),
                    DailyKpiRow(date: "2026-10-03", values: ["steps": 800])]
        let input = GoalsBoardInputs.build(goals: goals, dailyRows: rows, gateAverages: nil, nutrition: nutrition, energyDays: [],
                                           avgDeficit7d: nil, trackingDays: 0, today: today)
        #expect(input.yesterdayKcal == 1619)
        #expect(input.kcalDate == "2026-09-30")
        #expect(input.yesterdayProteinG == 127)
        #expect(input.yesterdaySteps == 12000)
        #expect(input.stepsDate == "2026-10-01")
        let byTitle = Dictionary(uniqueKeysWithValues: input.targetRows(macros: nil).map { ($0.title, $0.value) })
        #expect(byTitle["Calories"] == "1,619 kcal · 30 Sep")
        #expect(byTitle["Protein"] == "127 g · 30 Sep")
        #expect(byTitle["Daily steps"] == "12,000 · 1 Oct")
    }

    @Test func energyDaysFillCaloriesWhenNutritionHasNone() {
        let input = GoalsBoardInputs.build(goals: goals, dailyRows: [], gateAverages: nil, nutrition: [],
                                           energyDays: [EnergyDay(date: "2026-10-01", kcalConsumed: 1500)],
                                           avgDeficit7d: nil, trackingDays: 0, today: today)
        #expect(input.yesterdayKcal == 1500)
        #expect(input.kcalDate == "2026-10-01")
    }

    @Test func gateAverageWeightHasNoDate() throws {
        let avg = try JSON.decoder.decode(GateAverages.self, from: Data(#"{"avg_weight_kg": 79.9, "trends": {}}"#.utf8))
        let input = GoalsBoardInputs.build(goals: goals, dailyRows: [], gateAverages: avg, nutrition: [], energyDays: [],
                                           avgDeficit7d: nil, trackingDays: 0, today: today)
        #expect(input.latestWeightText == "79.9 kg")
    }

    @Test func noReadingsStayMissing() {
        let input = GoalsBoardInputs.build(goals: goals, dailyRows: [], gateAverages: nil, nutrition: [], energyDays: [],
                                           avgDeficit7d: nil, trackingDays: 0, today: today)
        #expect(input.latestWeightText == nil)
        let steps = input.targetRows(macros: nil).first { $0.title == "Daily steps" }
        #expect(steps?.value == "— \(JIMissingReason.noData.rawValue)")
    }

    @Test func todaysWeighInSaysToday() {
        let rows = [DailyKpiRow(date: today, values: ["weight_kg": 79.1])]
        let input = GoalsBoardInputs.build(goals: goals, dailyRows: rows, gateAverages: nil, nutrition: [], energyDays: [],
                                           avgDeficit7d: nil, trackingDays: 0, today: today)
        #expect(input.latestWeightText == "79.1 kg · today")
    }
}

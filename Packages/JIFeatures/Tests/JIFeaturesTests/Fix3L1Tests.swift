import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

// W-FIX3 L1: BUG-34…39, BUG-51, the Nutrition / Energy parts of BUG-33, C-d (protein role).

// MARK: - BUG-34: the header names the selected day, never "Today" or a raw ISO date

@Test func nutritionHeaderNamesTheSelectedDay() {
    #expect(nutritionSubtitle(selected: "2026-09-24", today: "2026-09-25") == "Thursday · 24 Sep")
    #expect(nutritionSubtitle(selected: "2026-09-25", today: "2026-09-25") == "Today · 25 Sep")
    #expect(nutritionSectionTitle(selected: "2026-09-24", today: "2026-09-25") == "Thursday")
    #expect(nutritionSectionTitle(selected: "2026-09-25", today: "2026-09-25") == "Today")
    #expect(macroCardTitle(date: "2026-09-24", today: "2026-09-25") == "Macros · Thursday")
    #expect(macroCardTitle(date: "2026-09-25", today: "2026-09-25") == "Macros today")
    // Never a raw ISO date anywhere in the header.
    #expect(!nutritionSubtitle(selected: "2026-09-24", today: "2026-09-25").contains("2026"))
    #expect(nutritionWeekCaption(date: "2026-09-24", kcal: 1183.4) == "Thursday 24 Sep · 1183 kcal")
    #expect(nutritionWeekCaption(date: "2026-09-24", kcal: nil) == "Thursday 24 Sep · — No data")
}

// MARK: - BUG-35: the goal shows next to "—" on a day with no food yet

@Test func kcalGoalShowsWhenNothingIsLoggedYet() {
    #expect(macroHeroGoalText(1738.6) == "/ 1739 kcal")
    #expect(macroHeroGoalText(nil) == "kcal")
    #expect(macroKcalStatus(kcal: nil, goal: 1738.5, isToday: true) == "— No data")
    #expect(nutritionKcalGoal(dayGoal: nil, weekGoal: 1738.5, goalsGoal: 1700) == 1738.5)
    #expect(nutritionKcalGoal(dayGoal: 1617, weekGoal: 1738.5, goalsGoal: nil) == 1617)
    #expect(nutritionKcalGoal(dayGoal: nil, weekGoal: nil, goalsGoal: 1700) == 1700)
    #expect(nutritionKcalGoal(dayGoal: nil, weekGoal: nil, goalsGoal: nil) == nil)
}

// MARK: - BUG-36 / BUG-51: one rounding rule, no locale grouping

@Test func nutritionNumbersRoundLikeEveryOtherScreen() {
    #expect(nutritionWholeText(37.8) == "38")        // was truncated to "37"
    #expect(nutritionWholeText(1183.4) == "1183")    // plain digits, never "1'183"
    #expect(nutritionWholeText(nil) == "—")
    #expect(nutritionWholeText(.nan) == "—")
    #expect(mealItemKcalText(526.6) == "527 kcal")
    #expect(mealItemKcalText(nil) == "— No data")
}

@Test func macroHeroStatusMatchesTheBoard() {
    #expect(macroKcalStatus(kcal: 467, goal: 1617, isToday: true) == "On track")
    #expect(macroKcalStatus(kcal: 1900, goal: 1617, isToday: true) == "283 kcal over goal")
    #expect(macroKcalStatus(kcal: 1619, goal: 1617, isToday: false) == "On target")
    #expect(macroKcalStatus(kcal: 1200, goal: 1617, isToday: false) == "Below target")
    #expect(macroKcalStatus(kcal: 1900, goal: 1617, isToday: false) == "Over target")
    #expect(macroKcalStatus(kcal: 1200, goal: nil, isToday: false) == "No goal set")
}

@Test func macroBarsShowValueAgainstGoal() {
    let total = NutritionDayTotal(kcal: 467, kcalGoal: 1617, proteinG: 52.4, carbsG: 27, fatG: nil)
    let rows = macroSummaryRows(total, goal: NutritionGoal(proteinG: 155, carbsG: nil, fatG: 60))
    #expect(rows.map(\.label) == ["Protein", "Carbs", "Fat"])
    #expect(rows.map(\.text) == ["52 / 155 g", "27 g", "— No data"])
    #expect(rows[0].fraction.map { abs($0 - 52.4 / 155) < 0.0001 } == true)
    #expect(rows[1].fraction == nil)   // no carbs goal → no bar, never a bar against a guess
    #expect(rows[2].fraction == nil)
}

// MARK: - C-d: protein uses the macro role everywhere

@Test func proteinUsesTheProteinRole() {
    let rows = macroSummaryRows(NutritionDayTotal(proteinG: 10, carbsG: 10, fatG: 10), goal: nil)
    #expect(rows.map(\.role) == [.protein, .carbs, .fat])
    let d = mealDetail(slot: "lunch", items: [NutritionMealItem(name: "x", kcal: 1, proteinG: 1, carbsG: 1, fatG: 1)])
    #expect(mealDetailRows(d).map(\.role) == [.kcal, .protein, .carbs, .fat])
}

// MARK: - BUG-51: the board's "Yesterday" cards

@Test func yesterdayCardsComeFromTheWeek() {
    let week = [NutritionDailyRow(date: "2026-09-23", kcalConsumed: 1619, kcalGoal: 1617, proteinG: 127),
                NutritionDailyRow(date: "2026-09-24", kcalConsumed: 467, kcalGoal: 1617, proteinG: 52)]
    let y = nutritionPreviousDay(week: week, selected: "2026-09-24")
    #expect(y?.date == "2026-09-23")
    #expect(nutritionPreviousDay(week: week, selected: "2026-09-23") == nil)
    #expect(nutritionProteinStatus(protein: 127, goal: 155) == "Below target")
    #expect(nutritionProteinStatus(protein: 150, goal: 155) == "On target")
    #expect(nutritionProteinStatus(protein: nil, goal: 155) == "— No data")
    #expect(nutritionProteinStatus(protein: 127, goal: nil) == "No goal set")
}

// MARK: - BUG-37: WeeklyPlan targets are whole numbers

@Test func weeklyPlanTargetsAreWholeNumbers() {
    #expect(weeklyPlanTargetText(184.9) == "185")
    #expect(weeklyPlanTargetText(59.125) == "59")
    #expect(weeklyPlanTargetText(1800) == "1800")
    let d = DayPlan(day: .sat, high: false, kcal: 1617, protein: 184.9, carbs: 120, fat: 59.125)
    #expect(weeklyPlanDayAccessibilityLabel(d) == "Sat, rest day: 1617 kcal, 185 g protein, 120 g carbs, 59 g fat")
}

// MARK: - BUG-38: "What you burn" shows the hub's burn, or a true reason

@Test func burnCardShowsTheSevenDayAverage() {
    let days = [EnergyDay(date: "2026-09-22", tdeeRaw: 2300, tdeeCorrected: 2200),
                EnergyDay(date: "2026-09-23", tdeeRaw: 2400, tdeeCorrected: nil),
                EnergyDay(date: "2026-09-24", tdeeRaw: nil, tdeeCorrected: nil),
                EnergyDay(date: "2026-09-25", tdeeRaw: 900, tdeeCorrected: 900)]   // today: still filling in
    #expect(energyBurnAverage(days: days, today: "2026-09-25") == 2350)   // measured totals only
    #expect(energyBurnText(days: days, today: "2026-09-25") == "2350 kcal")
    // A modelled (empirical) burn alone is not a measured one → no value, a reason word.
    #expect(energyBurnAverage(days: [EnergyDay(date: "2026-09-24", tdeeCorrected: 2250)], today: "2026-09-25") == nil)
    #expect(energyBurnText(days: [], today: "2026-09-25") == "— No data")
    #expect(!energyBurnText(days: [], today: "2026-09-25").contains("Not in Health yet"))
}

// MARK: - BUG-39: the Daily log uses the explainer's words and the plan band

@Test func dailyLogLabelsFollowTheExplainerRule() {
    // Band = goal ± 5 %: 1617 → 1536…1698.
    #expect(energyPlanBandText(1617) == "Plan band 1536–1698 kcal")
    #expect(energyPlanBandText(nil) == "No goal set")
    #expect(energyDayStatus(intake: 1619, goal: 1617, deficit: 600) == .onPlan)
    #expect(energyDayStatus(intake: 1200, goal: 1617, deficit: 1000) == .deepDeficit)
    #expect(energyDayStatus(intake: 1900, goal: 1617, deficit: 200) == .lightDeficit)
    #expect(energyDayStatus(intake: 2600, goal: 1617, deficit: -300) == .surplus)
    #expect(energyDayStatus(intake: 1900, goal: 1617, deficit: nil) == .abovePlan)
    #expect(energyDayStatus(intake: nil, goal: 1617, deficit: nil) == .missing(.noData))
    #expect(energyDayStatus(intake: 1600, goal: nil, deficit: 100) == .noGoal)
    #expect(EnergyDayStatus.onPlan.word == "On plan")
    #expect(EnergyDayStatus.deepDeficit.word == "Deep deficit")
    #expect(EnergyDayStatus.lightDeficit.word == "Light deficit")
    #expect(EnergyDayStatus.surplus.word == "Surplus")
    // Every word the log can show is named in the explainer (or is a no-goal / missing reason).
    let rule = JIExplainers.energyBalanceSteps.map(\.body).joined(separator: " ")
    for s in [EnergyDayStatus.onPlan, .deepDeficit, .lightDeficit, .surplus] { #expect(rule.contains(s.word)) }
}

@Test func howWeCalculateAppearsOnce() {
    #expect(EnergySection.allCases.filter { $0 == .howWeCalculate }.count == 1)
    #expect(EnergySection.allCases == [.hero, .whatYouBurn, .howWeCalculate, .thisWeek])
}

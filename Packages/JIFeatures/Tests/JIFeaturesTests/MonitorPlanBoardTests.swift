import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// B-57 W1 r4 (g2): the Monitor / Plan board items — KpiDetailNutrition hero + trend line,
// KpiDetail status, Energy "This week" + daily log, WeeklyPlan goal status + Save plan.

@Suite struct KpiNutritionHeroTests {
    @Test func goalTextIsTheUsersGoalOrNoGoalSet() {
        #expect(kpiMacroHeroGoalText(goal: 155, unit: "g", decimals: 0) == "/ 155 g goal")
        #expect(kpiMacroHeroGoalText(goal: 1617, unit: "kcal", decimals: 0) == "/ 1617 kcal goal")
        #expect(kpiMacroHeroGoalText(goal: nil, unit: "g", decimals: 0) == "no goal set")
    }

    @Test func goalComesFromTheGoalsDocument() {
        let g = NutritionGoal(kcalGoal: 1617, proteinG: 155, carbsG: nil, fatG: 54)
        #expect(kpiMacroGoal(g, .kcal) == 1617)
        #expect(kpiMacroGoal(g, .protein) == 155)
        #expect(kpiMacroGoal(g, .carbs) == nil)
        #expect(kpiMacroGoal(g, .fat) == 54)
        #expect(kpiMacroGoal(nil, .protein) == nil)
    }

    @Test func statusBelowGoalSaysHowFarShortAndWhen() {
        let s = kpiMacroHeroStatus(value: 127, goal: 155, date: "2026-09-22", macro: .protein, unit: "g", decimals: 0)
        #expect(s?.word == "Below goal · 28 g short on 22 Sep")
        #expect(s?.role == .reduced)
        #expect(s?.symbolName == "arrow.down")
    }

    @Test func statusWithinFivePercentIsOnGoal() {
        let s = kpiMacroHeroStatus(value: 1619, goal: 1617, date: "2026-09-22", macro: .kcal, unit: "kcal", decimals: 0)
        #expect(s?.word == "On goal")
        #expect(s?.role == .go)
    }

    @Test func caloriesOverGoalIsNeverGreenProteinOverGoalIs() {
        let kcal = kpiMacroHeroStatus(value: 2000, goal: 1617, date: "2026-09-22", macro: .kcal, unit: "kcal", decimals: 0)
        #expect(kcal?.word == "Above goal · 383 kcal over on 22 Sep")
        #expect(kcal?.role == .reduced)
        let protein = kpiMacroHeroStatus(value: 180, goal: 155, date: "2026-09-22", macro: .protein, unit: "g", decimals: 0)
        #expect(protein?.role == .go)
    }

    @Test func noValueIsNoDataAndNoGoalIsNoStatus() {
        let missing = kpiMacroHeroStatus(value: nil, goal: 155, date: nil, macro: .protein, unit: "g", decimals: 0)
        #expect(missing?.word == "— No data")
        #expect(missing?.role == .muted)
        #expect(kpiMacroHeroStatus(value: 127, goal: nil, date: "2026-09-22", macro: .protein, unit: "g", decimals: 0) == nil)
    }

    @Test func trendLineIsUpDownOrSteadyAgainstThe28DayAverage() {
        let tail = "Days with nothing in Apple Health are skipped, not counted as zero."
        #expect(kpiMacroTrendLine(avg7: 140, avg28: 120) == "Up against your 28-day average. \(tail)")
        #expect(kpiMacroTrendLine(avg7: 100, avg28: 120) == "Down against your 28-day average. \(tail)")
        #expect(kpiMacroTrendLine(avg7: 120.5, avg28: 120) == "Steady against your 28-day average. \(tail)")
        #expect(kpiMacroTrendLine(avg7: nil, avg28: nil) == "— No data yet to compare. \(tail)")
    }

    @Test func kcalCarriesTheKcalTint() {
        #expect(kpiMacroTintRole(.kcal) == nutritionKcalTintRole)
        #expect(kpiMacroTintRole(.protein) == metricTintRole("protein"))
    }
}

@Suite struct KpiDetailStatusTests {
    private func series(_ values: [Double?]) -> [(date: String, value: Double?)] {
        values.enumerated().map { (date: String(format: "2026-09-%02d", $0.offset + 1), value: $0.element) }
    }

    @Test func downAgainstThe28DayAverage() {
        let h = series(Array(repeating: 50, count: 20) + [40])
        let s = kpiDetailStatus(history: h, value: 40, unit: "ms", decimals: 0)
        #expect(s.word == "Down")
        #expect(s.symbolName == "arrow.down")
        #expect(s.detail == "Your last reading against your 28-day average of 50 ms.")
    }

    @Test func steadyWithinTwoPercent() {
        let h = series(Array(repeating: 50, count: 20))
        #expect(kpiDetailStatus(history: h, value: 50, unit: "ms", decimals: 0).word == "Steady")
    }

    @Test func fewerThanSevenReadingsIsCalibrating() {
        let h = series([50, nil, 52, nil, 48])
        let s = kpiDetailStatus(history: h, value: 48, unit: "ms", decimals: 0)
        #expect(s.word == "— Calibrating")
        #expect(s.detail == "JI compares against your 28-day average once it has 7 readings (3 so far).")
    }

    @Test func noValueIsNoData() {
        #expect(kpiDetailStatus(history: [], value: nil, unit: "ms", decimals: 0).word == "— No data")
    }
}

@Suite struct EnergyWeekTests {
    private static let days: [EnergyDay] = [
        EnergyDay(date: "2026-09-20", kcalConsumed: nil),
        EnergyDay(date: "2026-09-21", kcalConsumed: 1549),
        EnergyDay(date: "2026-09-22", kcalConsumed: 1619),
        EnergyDay(date: "2026-09-23", kcalConsumed: 467),
    ]

    @Test func weekRunsMondayToSundayWithTodayAndFutureMarked() {
        let bars = energyWeekBars(days: Self.days, today: "2026-09-23")
        #expect(bars.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(bars.map(\.kcal) == [1549, 1619, 467, nil, nil, nil, nil])
        #expect(bars.map(\.isToday) == [false, false, true, false, false, false, false])
        #expect(bars[3].isFuture && !bars[1].isFuture)
    }

    @Test func fillingInCaptionOnlyWhenTodayHasIntake() {
        #expect(energyFillingInCaption(days: Self.days, today: "2026-09-23") == "Wednesday is still filling in.")
        #expect(energyFillingInCaption(days: Self.days, today: "2026-09-24") == nil)
    }

    @Test func logIsCompleteDaysNewestFirst() {
        let log = energyLogDays(days: Self.days, today: "2026-09-23")
        #expect(log.map(\.date) == ["2026-09-22", "2026-09-21", "2026-09-20"])
        #expect(energyLogDateLabel("2026-09-22") == "Tue 22")
    }

    /// W-FIX3 BUG-39: the log speaks the explainer's plan-band words (see Fix3L1Tests).
    @Test func dayStatusAgainstThePlanBand() {
        #expect(energyDayStatus(intake: 1619, goal: 1617) == .onPlan)
        #expect(energyDayStatus(intake: 1549, goal: 1617) == .onPlan)   // within 5 %
        #expect(energyDayStatus(intake: 1900, goal: 1617, deficit: 300) == .lightDeficit)
        #expect(energyDayStatus(intake: 1200, goal: 1617) == .deepDeficit)
        #expect(energyDayStatus(intake: nil, goal: 1617) == .missing(.noData))
        #expect(energyDayStatus(intake: 1600, goal: nil) == .noGoal)
        #expect(EnergyDayStatus.onPlan.word == "On plan")
        #expect(EnergyDayStatus.missing(.noData).word == "— No data")
        #expect(EnergyDayStatus.noGoal.word == "No goal set")
        #expect(EnergyDayStatus.onPlan.role == .go)
    }
}

@Suite @MainActor struct WeeklyPlanGoalAndSaveTests {
    @Test func goalStatusMatchesOrSaysByHowMuch() {
        #expect(weeklyPlanGoalStatus(avgKcal: 1617, goalKcal: 1617) == WeeklyPlanGoalStatus(word: "Matches your goal", role: .go, symbolName: "checkmark"))
        #expect(weeklyPlanGoalStatus(avgKcal: 1700, goalKcal: 1617).word == "83 kcal above your goal of 1617")
        #expect(weeklyPlanGoalStatus(avgKcal: 1500, goalKcal: 1617).word == "117 kcal below your goal of 1617")
        #expect(weeklyPlanGoalStatus(avgKcal: 1500, goalKcal: 1617).role == .reduced)
        #expect(weeklyPlanGoalStatus(avgKcal: 1617, goalKcal: nil).word == "No goal set")
        #expect(weeklyPlanGoalStatus(avgKcal: 1617, goalKcal: nil).role == .muted)
    }

    @Test func capNoteIsAStatusLinePlusItsReason() throws {
        let plan = computePeriodizedPlan(PeriodizedPlanInput(weeklyAvgKcal: 1800, trainKcal: 2200, proteinG: 165, fatG: 55))
        let line = try #require(weeklyPlanCapStatus(plan))
        #expect(line.word == "Training days held at \(plan.trainKcal) kcal")
        #expect(line.role == .reduced)
        #expect(weeklyPlanCapStatusDetail(plan)?.hasPrefix("The rest day can't bank more") == true)
    }

    @Test func goalComesFromTheGoalsDocument() async throws {
        let vm = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())), goalsProvider: MockDataProvider())
        await vm.load()
        #expect(vm.goalKcal == 1935)
        #expect(vm.goalStatus.word == "Matches your goal")
    }

    @Test func noProviderMeansNoGoalSet() async throws {
        let vm = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())))
        await vm.load()
        #expect(vm.goalKcal == nil)
        #expect(vm.goalStatus.word == "No goal set")
    }

    @Test func editsWaitForSavePlan() async throws {
        let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
        let vm = WeeklyPlanViewModel(store: store)
        await vm.load()
        #expect(vm.canSave)          // the plan on screen has never been saved
        vm.step(.protein, by: -5)
        #expect(store.load() == nil) // no write-through any more
        #expect(!vm.hasSaved)
        vm.save()
        #expect(vm.hasSaved)
        #expect(store.load()?.proteinG == 160)
        #expect(!vm.canSave)         // nothing changed since the save
        vm.step(.protein, by: 5)
        #expect(vm.canSave)
    }
}

// B-57 W1 r5 (h2): Energy hero as the board's "−598 kcal a day", WeeklyPlan's one kcal format,
// and the macro colour roles on the nutrition screens.
@Suite struct EnergyHeroBoardTests {
    @Test func numeralIsTheSignedSevenDayBalanceWithoutUnit() {
        #expect(energyHeroNumeral(598) == "\u{2212}598")    // deficit reads as a negative balance
        #expect(energyHeroNumeral(-120.4) == "+120")         // surplus
        #expect(energyHeroNumeral(0.3) == "0")
        #expect(energyHeroNumeral(nil) == "—")
        #expect(energyHeroNumeral(.nan) == "—")
    }

    @Test func directionFollowsTheSignOnlyNeverABand() {
        #expect(energyHeroDirection(598)?.word == "Deficit")
        #expect(energyHeroDirection(598)?.symbolName == "arrow.down")
        #expect(energyHeroDirection(-50)?.word == "Surplus")
        #expect(energyHeroDirection(-50)?.symbolName == "arrow.up")
        #expect(energyHeroDirection(0.2)?.word == "Even")
        #expect(energyHeroDirection(nil) == nil)
    }

    @Test func explanationUsesOnlyRealFigures() {
        #expect(energyHeroExplanation(avgDeficit: 598, trackingDays: 6, goal: 1617)
                == "You are eating less than you burn, averaged over 6 of the last 7 days. Your goal is 1617 kcal a day.")
        #expect(energyHeroExplanation(avgDeficit: -200, trackingDays: 7, goal: nil)
                == "You are eating more than you burn, averaged over 7 of the last 7 days. No goal set.")
        #expect(energyHeroExplanation(avgDeficit: 0, trackingDays: 5, goal: 1800)
                == "What you eat matches what you burn, averaged over 5 of the last 7 days. Your goal is 1800 kcal a day.")
        #expect(energyHeroExplanation(avgDeficit: nil, trackingDays: 5, goal: 1800)
                == "— No data for the last 7 days yet.")
    }
}

@Suite struct NutritionTintAndFormatTests {
    @Test func kcalCarriesTheMacroKcalRole() {
        #expect(nutritionKcalTintRole == .kcal)
        #expect(kpiMacroTintRole(.kcal) == .kcal)
        #expect(kpiMacroTintRole(.protein) == .protein)
        #expect(kpiMacroTintRole(.carbs) == .carbs)
        #expect(kpiMacroTintRole(.fat) == .fat)
    }

    @Test func weeklyPlanKnobsCarryTheirMacroRole() {
        #expect(weeklyPlanKnobTintRole(.weeklyAvg) == .kcal)
        #expect(weeklyPlanKnobTintRole(.trainKcal) == .kcal)
        #expect(weeklyPlanKnobTintRole(.protein) == .protein)
        #expect(weeklyPlanKnobTintRole(.fat) == .fat)
    }

    @Test func weeklyPlanKcalHasNoGroupingLikeTheBoard() {
        #expect(weeklyPlanKcalText(1907) == "1907")
        #expect(weeklyPlanKcalText(1617) == "1617")
        #expect(weeklyPlanKcalText(12000) == "12000")
    }
}

@Suite struct EnergyAX3LabelTests {
    @Test func weekdayShortensToTwoLettersOnlyAtAccessibilitySizes() {
        #expect(energyWeekdayLabel("Wed", accessibilitySize: false) == "Wed")
        #expect(energyWeekdayLabel("Wed", accessibilitySize: true) == "We")
    }
}

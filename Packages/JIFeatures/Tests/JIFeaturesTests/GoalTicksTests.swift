import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// B-57 W2 C3 (B-73): goal ticks and captions come from the user's own goals. Unset → no tick,
// "Set your goal"; never YAZIO's 1617 or the hub's seeded 1935.

/// Test values a user typed. JI ships none.
private let userGoals = MacroGoals(kcal: KcalGoal(goalKcal: 1800, basis: .includesDeficit), proteinG: 155, carbsG: 144, fatG: 49)
private let user = NutritionGoalsSnapshot(macros: userGoals)
private let total = NutritionDayTotal(kcal: 1500, kcalGoal: 1617, proteinG: 127, carbsG: 100, fatG: 40, mealsLogged: 3)

@Test func macroBarsUseTheUsersGoalsNotTheHubDocument() {
    let rows = macroSummaryRows(total, goals: user)
    #expect(rows.map(\.text) == ["127 / 155 g", "100 / 144 g", "40 / 49 g"])
    #expect(rows.allSatisfy { $0.fraction != nil })
}

@Test func unsetMacroGoalsDrawNoBarAndSaySo() {
    for goals in [NutritionGoalsSnapshot.unknown, NutritionGoalsSnapshot(macros: .unset)] {
        let rows = macroSummaryRows(total, goals: goals)
        #expect(rows.map(\.text) == ["127 g · Set your goal", "100 g · Set your goal", "40 g · Set your goal"])
        #expect(rows.allSatisfy { $0.fraction == nil })
    }
    let partial = macroSummaryRows(total, goals: NutritionGoalsSnapshot(macros: MacroGoals(proteinG: 155)))
    #expect(partial[0].fraction != nil)
    #expect(partial[1].text == "100 g · Set your goal")
    // A missing actual is still "— No data", goal or not.
    #expect(macroSummaryRows(NutritionDayTotal(), goals: user)[0].text == "— No data")
}

@Test func kcalHeroStatusSaysSetYourGoalWhenUnset() {
    #expect(macroKcalStatus(kcal: 1200, goal: nil, isToday: false) == "Set your goal")
    #expect(nutritionProteinStatus(protein: 127, goal: nil) == "Set your goal")
    #expect(macroKcalStatus(kcal: 1500, goal: user.kcalGoal, isToday: true) == "On track")
}

@Test func kpiDetailNutritionGoalCellsAndHero() {
    let s = KpiMacroSummary(latestDate: "2026-09-23", latest: 127, avg7: 131, avg28: 128)
    #expect(kpiMacroTableCells(s, decimals: 0, unit: "g", goal: user.goal(for: .protein)) == ["155 g", "127 g", "131 g", "128 g"])
    #expect(kpiMacroTableCells(s, decimals: 0, unit: "g", goal: NutritionGoalsSnapshot.unknown.goal(for: .protein))[0] == "Set your goal")
    #expect(kpiMacroHeroGoalText(goal: user.goal(for: .protein), unit: "g", decimals: 0) == "/ 155 g goal")
    #expect(kpiMacroHeroGoalText(goal: nil, unit: "g", decimals: 0) == "Set your goal")
}

@Test func trendsTicksOnlyNutritionCardsWithASetGoal() {
    let cards = trendsCards(recovery: [], daily: [], averages: nil)
    let byId = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
    #expect(trendsGoal(byId["kcal"]!, user) == 1800)
    #expect(trendsGoal(byId["protein"]!, user) == 155)
    #expect(trendsGoal(byId["fat"]!, user) == 49)
    #expect(trendsGoal(byId["hrv"]!, user) == nil)
    #expect(trendsGoal(byId["protein"]!, .unknown) == nil)
}

@Test func kpiListNutritionSquaresCaptionTheGoal() {
    let items = kpiCatalogueItems(group: .onToday, visible: [.kcal, .protein, .carbs, .hrv],
                                  value: { id in KpiReading(value: id == .kcal ? 1750 : 120, date: "2026-09-25") },
                                  today: "2026-09-25", goalCaption: { user.caption(for: $0, value: $1) })
    let captions = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.goalText) })
    #expect(captions["kcal"] == "On goal")
    #expect(captions["protein"] == "/ 155 g")
    #expect(captions["carbs"] == "/ 144 g")
    #expect(captions["hrv"] == .some(nil))
    let unset = kpiCatalogueItems(group: .onToday, visible: [.protein], value: { _ in KpiReading(value: 120, date: "2026-09-25") },
                                  today: "2026-09-25", goalCaption: { NutritionGoalsSnapshot(macros: .unset).caption(for: $0, value: $1) })
    #expect(unset[0].goalText == "Set your goal")
}

@Test @MainActor func weeklyPlanStartsFromTheUsersGoalsBeforeTheHub() async throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    let vm = WeeklyPlanViewModel(store: store, goalsProvider: MockDataProvider(), jiGoals: { userGoals })
    await vm.load()
    #expect(vm.weeklyAvgKcal == 1800)          // the user's target, not the hub document's 1935
    #expect(vm.proteinG == 155)
    #expect(vm.fatG == 49)
    #expect(vm.goalKcal == 1800)
    #expect(vm.usesDefaultGoals == false)
}

@Test @MainActor func weeklyPlanIgnoresUnsetGoalsButNeverShowsTheHubKcalAsTheGoal() async throws {
    let withUnset = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())),
                                        goalsProvider: MockDataProvider(), jiGoals: { .unset })
    let without = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())),
                                      goalsProvider: MockDataProvider())
    await withUnset.load(); await without.load()
    #expect(withUnset.weeklyAvgKcal == without.weeklyAvgKcal)   // unset → falls through to the hub seed
    #expect(withUnset.goalKcal == nil)                           // but the seeded hub kcal is not "your goal"
}

/// C3 amendment (Toby 2026-09-24): defaults stay on WeeklyPlan, disclosed.
@Test @MainActor func weeklyPlanDisclosesDefaultsWhenGoalsUnset() async throws {
    let vm = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())), jiGoals: { nil })
    await vm.load()
    #expect(vm.weeklyAvgKcal == 1800)
    #expect(vm.usesDefaultGoals == true)
    #expect(WeeklyPlanViewModel.defaultsDisclaimer == "Default values in use. Set your own in Goals.")
}

@Test @MainActor func weeklyPlanDropsDisclaimerOnceAGoalIsSet() async throws {
    let goals = MacroGoals(kcal: KcalGoal(goalKcal: 1600, basis: .includesDeficit), proteinG: 150)
    let vm = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())), jiGoals: { goals })
    await vm.load()
    #expect(vm.usesDefaultGoals == false)
    #expect(vm.weeklyAvgKcal == 1600)
}

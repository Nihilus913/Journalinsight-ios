import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

// W5b-L5 (P-weekly-plan). Ports `mobile/__tests__/weeklyPlan.test.ts` (math) +
// `mobile/__tests__/lib/weeklyPlanStore.test.ts` (persistence), plus the screen's seeding
// priority from `mobile/app/weekly-plan.tsx`.

private let base = WeeklyPlanInput(dailyTargetKcal: 1800, highDays: [.sat, .sun], boostKcal: 400, proteinG: 165, fatG: 55)

private func day(_ plan: WeeklyPlan, _ d: WeekDay) -> DayPlan { plan.days.first { $0.day == d }! }

// MARK: computeWeeklyPlan (weeklyPlan.test.ts)

@Test func weeklyAverageIsPreserved() {
    let p = computeWeeklyPlan(base)
    #expect(p.avgKcal == 1800)
    #expect(p.weeklyKcal == 1800 * 7)
}

@Test func highDaysRunTheSurplusLowDaysAreBankedDown() {
    let p = computeWeeklyPlan(base)
    #expect(day(p, .sat).kcal == 2200) // 1800 + 400
    #expect(day(p, .mon).kcal == 1640) // 1800 - (400*2/5)
    #expect(day(p, .sat).high)
    #expect(!day(p, .mon).high)
}

@Test func proteinAndFatConstantCarbsAbsorbTheSwing() {
    let p = computeWeeklyPlan(base)
    #expect(p.days.allSatisfy { $0.protein == 165 && $0.fat == 55 })
    #expect(day(p, .sat).carbs > day(p, .mon).carbs)
}

@Test func noHighDaysMeansFlatWeekAtTarget() {
    var input = base
    input.highDays = []
    let p = computeWeeklyPlan(input)
    #expect(p.days.allSatisfy { $0.kcal == 1800 })
    #expect(p.avgKcal == 1800)
}

@Test func jsRoundMatchesMathRoundOnHalves() {
    #expect(jsRound(2.5) == 3)
    #expect(jsRound(-2.5) == -2) // Math.round(-2.5) === -2; Swift's .rounded() would give -3
    #expect(jsRound(1639.9999) == 1640)
}

// MARK: sessionTypeForWeekDay / isTrainingWeekDay

@Test func classifiesEveryWeekdayPerSessionByWeekday() {
    #expect(sessionTypeForWeekDay(.mon) == .strength)
    #expect(sessionTypeForWeekDay(.tue) == .interval)
    #expect(sessionTypeForWeekDay(.wed) == .strength)
    #expect(sessionTypeForWeekDay(.thu) == .z2)
    #expect(sessionTypeForWeekDay(.fri) == .strength)
    #expect(sessionTypeForWeekDay(.sat) == .interval)
    #expect(sessionTypeForWeekDay(.sun) == .rest)
}

@Test func onlyRestOrOptionalSlotsAreNonTrainingDays() {
    #expect(isTrainingWeekDay(.mon))
    #expect(isTrainingWeekDay(.sat))
    #expect(!isTrainingWeekDay(.sun))
}

@Test func trainingAndRestDaysPartitionTheWeek() {
    #expect(trainingWeekDays.count + restWeekDays.count == weekDays.count)
    for d in trainingWeekDays { #expect(!restWeekDays.contains(d)) }
    #expect(restWeekDays == [.sun])
}

// MARK: computePeriodizedPlan

private let periodizedBase = PeriodizedPlanInput(weeklyAvgKcal: 1800, trainKcal: 2200, proteinG: 165, fatG: 55)

@Test func periodizedWeeklyAverageIsPreserved() {
    let p = computePeriodizedPlan(periodizedBase)
    #expect(p.avgKcal == 1800)
    #expect(p.weeklyKcal == 1800 * 7)
}

@Test func everyTrainingDayHitsTargetRestDayBankedDown() {
    // A target the rest days can fund: 6 × 50 kcal banked off the one rest day.
    var input = periodizedBase
    input.trainKcal = 1850
    let p = computePeriodizedPlan(input)
    for d in p.days where trainingWeekDays.contains(d.day) {
        #expect(d.kcal == 1850)
        #expect(d.high)
    }
    let sun = p.days.first { $0.day == .sun }!
    #expect(!sun.high)
    #expect(sun.kcal == 1800 - 6 * 50)
    #expect(p.trainKcal == 1850)
    #expect(p.restKcal == sun.kcal)
    #expect(!p.trainCapped)
}

// MARK: B-57 W1 fixer — the rest day printed "-600" kcal
//
// Root cause: the schedule has 6 training days and 1 rest day, so a +400 training-day boost has
// to be banked entirely off Sunday: 1800 − 6 × 400 = −600. The banking math had no floor.

@Test func restDayNeverDropsBelowTheProteinAndFatHeldEveryDay() {
    let p = computePeriodizedPlan(periodizedBase)   // 1800 avg, 2200 train, 165 P, 55 F
    let floor = weeklyPlanDayFloorKcal(proteinG: 165, fatG: 55)
    #expect(floor == 165 * 4 + 55 * 9)
    #expect(p.days.allSatisfy { $0.kcal > 0 && Double($0.kcal) >= floor })
    #expect(p.days.allSatisfy { $0.carbs >= 0 })
    #expect(p.trainCapped)
    // The weekly average still holds; the training days take only what the rest day can fund.
    #expect(p.weeklyKcal == 1800 * 7)
    #expect(p.trainKcal == 1800 + Int(((1800 - floor) * 1 / 6).rounded(.down)))
    #expect(weeklyPlanMaxTrainKcal(weeklyAvgKcal: 1800, proteinG: 165, fatG: 55) == Double(p.trainKcal))
}

@Test func averageBelowTheFloorIsAFlatWeekNeverNegative() {
    let p = computePeriodizedPlan(PeriodizedPlanInput(weeklyAvgKcal: 1000, trainKcal: 1400, proteinG: 165, fatG: 55))
    #expect(p.days.allSatisfy { $0.kcal == 1000 })
}

@Test func capNoteNamesTheHeldTargetAndTheFloor() {
    let p = computePeriodizedPlan(periodizedBase)
    let note = weeklyPlanCapNote(p)
    #expect(note?.contains("\(p.trainKcal) kcal") == true)
    #expect(note?.contains("1155 kcal") == true)
    #expect(weeklyPlanCapNote(computePeriodizedPlan(PeriodizedPlanInput(weeklyAvgKcal: 1800, trainKcal: 1800, proteinG: 165, fatG: 55))) == nil)
}

@Test func periodizedTrainRestDaysMatchClassification() {
    let p = computePeriodizedPlan(periodizedBase)
    #expect(p.trainDays == trainingWeekDays)
    #expect(p.restDays == restWeekDays)
}

@Test func periodizedProteinFatConstant() {
    let p = computePeriodizedPlan(periodizedBase)
    #expect(p.days.allSatisfy { $0.protein == 165 && $0.fat == 55 })
}

@Test func trainKcalEqualToAverageIsAFlatWeek() {
    var input = periodizedBase
    input.trainKcal = 1800
    let p = computePeriodizedPlan(input)
    #expect(p.days.allSatisfy { $0.kcal == 1800 })
}

// MARK: WeeklyPlanStore (weeklyPlanStore.test.ts)

private let prefsFixture = WeeklyPlanPrefs(weeklyAvgKcal: 1800, trainKcal: 2200, proteinG: 165, fatG: 55)

@Test func storeReturnsNilWhenNothingSaved() throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    #expect(store.load() == nil)
}

@Test func storeSaveLoadRoundTrips() throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    store.save(prefsFixture)
    #expect(store.load() == prefsFixture)
}

@Test func storeSurvivesASimulatedRestart() throws {
    let db = try AppDatabase.inMemory()
    WeeklyPlanStore(prefs: PrefStore(db: db)).save(prefsFixture)
    // Cold-start simulation: a fresh store over the same underlying database.
    #expect(WeeklyPlanStore(prefs: PrefStore(db: db)).load() == prefsFixture)
}

@Test func laterSaveFullyReplacesPriorPrefs() throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    store.save(prefsFixture)
    var next = prefsFixture
    next.trainKcal = 2400
    store.save(next)
    #expect(store.load() == next)
}

@Test func storeUsesTheOracleKey() throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    WeeklyPlanStore(prefs: prefs).save(prefsFixture)
    #expect(try prefs.get("weekly_plan.periodized", as: WeeklyPlanPrefs.self) == prefsFixture)
}

@Test func nilStoreIsANoOpNotACrash() {
    let store = WeeklyPlanStore(prefs: nil)
    store.save(prefsFixture)
    #expect(store.load() == nil)
}

// MARK: WeeklyPlanViewModel seeding (weekly-plan.tsx)

@Test @MainActor func planRendersFromFixtureGoalsWhenNothingPersisted() async throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    let vm = WeeklyPlanViewModel(store: store, goalsProvider: MockDataProvider())
    await vm.load()
    // Fixtures/hub-contract/planning_goals.json: kcal_goal 1935, protein_g 184.9, fat_g 59.125.
    #expect(vm.weeklyAvgKcal == 1935)
    #expect(vm.trainKcal == 1935 + WeeklyPlanViewModel.defaultTrainBoost)
    #expect(vm.proteinG == 184.9)
    #expect(vm.fatG == 59.125)
    #expect(vm.plan.avgKcal == 1935)
    #expect(vm.plan.trainDays == trainingWeekDays)
    // 1935 + 400 cannot be banked off one rest day; Monday takes what Sunday can fund.
    #expect(vm.plan.trainCapped)
    #expect(vm.plan.days.first { $0.day == .mon }!.kcal == 2045)
    #expect(vm.plan.days.allSatisfy { $0.kcal > 0 })
    // Seeding alone never writes the prefs row (RN only persists on an edit).
    #expect(store.load() == nil)
}

@Test @MainActor func persistedPrefsWinOverGoals() async throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    store.save(prefsFixture)
    let vm = WeeklyPlanViewModel(store: store, goalsProvider: MockDataProvider())
    await vm.load()
    #expect(vm.weeklyAvgKcal == 1800)
    #expect(vm.trainKcal == 2200)
    #expect(vm.proteinG == 165)
}

@Test @MainActor func fallbackWhenNoPrefsAndNoProvider() async throws {
    let vm = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())))
    await vm.load()
    #expect(vm.weeklyAvgKcal == 1800)
    #expect(vm.trainKcal == 2200)
    #expect(vm.proteinG == 165)
    #expect(vm.fatG == 55)
}

@Test @MainActor func everyEditWritesThroughImmediately() async throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    let vm = WeeklyPlanViewModel(store: store)
    await vm.load()
    #expect(!vm.hasSaved)
    // The default 2200 is held at 1907 (see restDayNeverDropsBelow…); a step starts from what
    // the screen shows, and never climbs past what the rest day can fund.
    #expect(vm.value(of: .trainKcal) == 1907)
    vm.step(.trainKcal, by: 50)
    #expect(vm.hasSaved)
    #expect(store.load()?.trainKcal == 1907)
    vm.step(.trainKcal, by: -50)
    #expect(store.load()?.trainKcal == 1857)
    vm.step(.protein, by: -5)
    #expect(store.load()?.proteinG == 160)
}

@Test @MainActor func stepperFloorsMatchRN() async throws {
    let vm = WeeklyPlanViewModel(store: WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory())))
    await vm.load()
    for _ in 0..<20 { vm.step(.weeklyAvg, by: -50) }
    #expect(vm.weeklyAvgKcal == 1200)
    for _ in 0..<30 { vm.step(.trainKcal, by: -50) }
    #expect(vm.trainKcal == vm.weeklyAvgKcal) // min = weeklyAvgKcal
    for _ in 0..<30 { vm.step(.protein, by: -5) }
    #expect(vm.proteinG == 80)
    for _ in 0..<10 { vm.step(.fat, by: -5) }
    #expect(vm.fatG == 30)
}

@Test @MainActor func userEditWinsOverALaggingGoalsSeed() async throws {
    let store = WeeklyPlanStore(prefs: PrefStore(db: try AppDatabase.inMemory()))
    let vm = WeeklyPlanViewModel(store: store, goalsProvider: SlowGoalsProvider())
    let load = Task { await vm.load() }
    try await Task.sleep(for: .milliseconds(10)) // load() is now parked inside goals()
    vm.step(.weeklyAvg, by: 50) // user edits while goals() is still in flight
    await load.value
    #expect(vm.weeklyAvgKcal == 1850) // the seed did not clobber the edit
    #expect(store.load()?.weeklyAvgKcal == 1850)
}

@Test func numberTextDropsTrailingZeroOnlyForWholeNumbers() {
    #expect(weeklyPlanNumberText(1800) == "1800")
    #expect(weeklyPlanNumberText(184.9) == "184.9")
    #expect(weeklyPlanNumberText(59.125) == "59.125")
}

nonisolated struct SlowGoalsProvider: EnergyProviding {
    func energy(windowDays: Int) async throws -> EnergyReport { throw HubError.network("test") }
    func goals() async throws -> Goals {
        try await Task.sleep(for: .milliseconds(50))
        return try await MockDataProvider().goals()
    }
}

// MARK: B-57 W1 board restyle (bar per day, board copy)

@Suite @MainActor struct WeeklyPlanBoardTests {
    @Test func barFractionIsRelativeToTheTallestDay() {
        let days = [DayPlan(day: .mon, high: true, kcal: 2000, protein: 165, carbs: 200, fat: 55),
                    DayPlan(day: .tue, high: false, kcal: 1500, protein: 165, carbs: 100, fat: 55)]
        #expect(weeklyPlanBarFraction(kcal: 2000, days: days) == 1)
        #expect(weeklyPlanBarFraction(kcal: 1500, days: days) == 0.75)
        #expect(weeklyPlanBarFraction(kcal: 1500, days: []) == 0)
    }

    @Test func boardCopyAndLabels() {
        #expect(WeeklyPlanViewModel.Knob.protein.label == "Protein, every day")
        #expect(WeeklyPlanViewModel.Knob.fat.label == "Fat, every day")
        #expect(weeklyPlanTrainDaysText(4) == "4 training days")
        #expect(weeklyPlanTrainDaysText(1) == "1 training day")
        let d = DayPlan(day: .sat, high: false, kcal: 1617, protein: 155, carbs: 120, fat: 55)
        #expect(weeklyPlanDayAccessibilityLabel(d) == "Sat, rest day: 1617 kcal, 155 g protein, 120 g carbs, 55 g fat")
    }

    @Test func todayMapsToMondayFirstWeekDay() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        // 2026-09-24 is a Thursday; 2026-09-27 a Sunday.
        #expect(weeklyPlanToday(c.date(from: DateComponents(year: 2026, month: 9, day: 24))!, calendar: c) == .thu)
        #expect(weeklyPlanToday(c.date(from: DateComponents(year: 2026, month: 9, day: 27))!, calendar: c) == .sun)
    }
}

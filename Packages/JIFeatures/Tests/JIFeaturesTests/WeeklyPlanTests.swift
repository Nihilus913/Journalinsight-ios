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
    let p = computePeriodizedPlan(periodizedBase)
    for d in p.days where trainingWeekDays.contains(d.day) {
        #expect(d.kcal == 2200)
        #expect(d.high)
    }
    let sun = p.days.first { $0.day == .sun }!
    #expect(!sun.high)
    #expect(sun.kcal < 1800)
    #expect(p.trainKcal == 2200)
    #expect(p.restKcal == sun.kcal)
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
    #expect(vm.plan.days.first { $0.day == .mon }!.kcal == 2335)
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
    vm.step(.trainKcal, by: 50)
    #expect(vm.hasSaved)
    #expect(store.load()?.trainKcal == 2250)
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

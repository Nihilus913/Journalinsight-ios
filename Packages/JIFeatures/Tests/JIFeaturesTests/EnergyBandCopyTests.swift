import Foundation
import Testing
import JICore
import JICompute
import JIDesign
import JIPersistence
@testable import JIFeatures

// B-57 W2 C2 (B-73): the Energy screen's band copy. Target 1800 is a test value a user typed.

private func band(_ intake: Double = 1800, target: Double = 1800, days: ClosedRange<Int> = 21...23) -> EnergyBandResult {
    EnergyBand.compute(targetKcal: target,
                       days: days.map { EnergyBandDay(date: "2026-09-\($0)", basalKcal: 1800, activeKcal: 500, intakeKcal: intake) },
                       today: "2026-09-24")
}

@Test func heroShowsBalanceAndClass() {
    let r = band()                             // burn 2300, eaten 1800 → −500, on plan
    #expect(EnergyBandCopy.heroValue(r) == "-500")
    #expect(EnergyBandCopy.heroReason(result: r, reason: nil) == "On plan")
    #expect(EnergyBandCopy.sentence(r) == "You are eating inside your plan band of 1700–1900 kcal a day.")
    #expect(EnergyBandCopy.planHeader(targetKcal: 1800) == "Plan 1800 kcal")
}

@Test func impliedDeficitIsInformationWithTheBurnGap() {
    #expect(EnergyBandCopy.impliedDeficit(band()) == "≈ 500 kcal under what you burn")
    #expect(EnergyBandCopy.impliedDeficit(band(target: 2600)) == "≈ 300 kcal over what you burn")
    #expect(EnergyBandCopy.impliedDeficit(band(days: 22...23)) == nil)     // calibrating
    #expect(EnergyBandCopy.impliedDeficit(nil) == nil)
}

@Test func missingDataIsADashPlusAReasonWord() {
    #expect(EnergyBandCopy.heroValue(nil) == "—")
    #expect(EnergyBandCopy.heroReason(result: nil, reason: "Calibrating") == "Calibrating")
    #expect(EnergyBandCopy.heroReason(result: nil, reason: "Not in Health yet") == "Not in Health yet")
    #expect(EnergyBandCopy.heroReason(result: nil, reason: nil) == "Set your goal")
    #expect(EnergyBandCopy.planHeader(targetKcal: nil) == "Set your goal")
    let dash = EnergyBandCopy.burn(nil)
    #expect([dash.total, dash.resting, dash.active] == ["—", "—", "—"])
}

@Test func calibratingKeepsTheBandButNotTheBalance() {
    let r = band(days: 22...23)
    #expect(EnergyBandCopy.heroValue(r) == "—")
    #expect(EnergyBandCopy.heroReason(result: r, reason: "Calibrating") == "Calibrating")
    #expect(r.bandLowKcal == 1700 && r.bandHighKcal == 1900)
}

@Test func burnCardValuesSplitRestingAndActive() {
    let b = EnergyBandCopy.burn(band().burn)
    #expect([b.total, b.resting, b.active] == ["2300", "1800", "500"])
}

@Test func settleNoteShowsUntilAFullWeek() {
    #expect(EnergyBandCopy.settleNote(band().burn) == "The band settles after a full week of Apple Health data.")
    #expect(EnergyBandCopy.settleNote(nil) == "The band settles after a full week of Apple Health data.")
    #expect(EnergyBandCopy.settleNote(band(days: 17...23).burn) == nil)
}

@Test func noteIsVerbatim() {
    #expect(EnergyBandCopy.noMedicalNote == "Watch and phone energy numbers are estimates. JI shows them as they are and makes no medical judgement from them.")
}

/// The shown explainer keeps PF-09's YAZIO lineage, and its band step is the user's target ± 100
/// with no JI-picked number.
@Test func howWeCalculateNamesTheUsersBandAndKeepsTheIntakeLineage() {
    #expect(energyHowWeCalculateSteps.count == 4)
    #expect(energyHowWeCalculateSteps[1].title == "Eaten = your YAZIO day total")
    #expect(energyHowWeCalculateSteps[3] == EnergyBandCopy.bandRuleStep)
    #expect(energyHowWeCalculateSteps[3].body.contains("the daily kcal target you set in Goals, ± 100 kcal"))
    #expect(!energyHowWeCalculateSteps.map(\.body).joined().contains("1617"))
}

/// Daily log + chart: the band is the user's target ± 100 (B-73), not ± 5 %.
@Test func dailyLogBandIsTheUsersTargetPlusMinus100() {
    #expect(energyPlanBandText(1800) == "Plan band 1700–1900 kcal")
    #expect(energyPlanBandText(nil) == "Set your goal")
    #expect(energyDayStatus(intake: 1890, goal: 1800, deficit: 400) == .onPlan)
    #expect(energyDayStatus(intake: 1650, goal: 1800, deficit: 700) == .deepDeficit)
    #expect(energyDayStatus(intake: 1950, goal: 1800, deficit: 300) == .lightDeficit)
    #expect(energyGoalHeaderText(1800) == "Plan 1800 kcal")
    #expect(energyGoalHeaderText(nil) == "Set your goal")
}

@Test @MainActor func viewModelReadsTheBandServiceNotTheHubGoal() async throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let store = MacroGoalsStore(prefs: prefs)
    try store.save(MacroGoals(kcal: KcalGoal(goalKcal: 1800, basis: .includesDeficit)))
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let service = EnergyBandService(reader: BandCopyTotalsFake(), store: store, cache: cache,
                                    now: { Date() }, dayKey: { _ in "2026-09-24" })
    let vm = EnergyViewModel(provider: MockDataProvider(), cache: cache, band: service)
    await vm.load()
    #expect(vm.goalKcal == 1800)                   // the user's target, never the hub goals document
    #expect(vm.bandState.result?.balanceClass == .onPlan)
    #expect(vm.bandState.burn?.burnKcal == 2300)
    let noBand = EnergyViewModel(provider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await noBand.load()
    #expect(noBand.goalKcal == nil)                // no user goal → "Set your goal", never the seeded hub number
    #expect(noBand.bandState == .none)
}

private nonisolated struct BandCopyTotalsFake: HealthDailyTotalsProviding {
    func dailyTotals(days: Int) async throws -> [HealthDailyTotals] {
        (17...24).map { HealthDailyTotals(date: "2026-09-\($0)", basalKcal: 1800, activeKcal: 500, dietaryKcal: 1800) }
    }
}

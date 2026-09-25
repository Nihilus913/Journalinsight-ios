import Foundation
import Testing
import JICore
import JICompute
import JIPersistence
@testable import JIFeatures

nonisolated struct TotalsFake: HealthDailyTotalsProviding {
    var rows: [HealthDailyTotals]
    var error: Error?
    func dailyTotals(days: Int) async throws -> [HealthDailyTotals] { if let error { throw error }; return rows }
}

private let today = "2026-09-24"
private let week: [HealthDailyTotals] = (17...24).map {
    HealthDailyTotals(date: "2026-09-\($0)", basalKcal: 1800, activeKcal: 500, dietaryKcal: $0 == 24 ? 600 : 1800, proteinG: $0 == 24 ? 52 : 150)
}

/// Test values a user typed. JI ships none.
private let subtract500 = MacroGoals(kcal: KcalGoal(goalKcal: 2300, basis: .subtractDeficit(.deficit(kcalPerDay: 500))), proteinG: 160)
private let includes1600 = MacroGoals(kcal: KcalGoal(goalKcal: 1600, basis: .includesDeficit))

@MainActor private func service(_ reader: (any HealthDailyTotalsProviding)?, goals: MacroGoals? = nil,
                                 cache: OfflineCache? = nil) throws -> EnergyBandService {
    let db = try AppDatabase.inMemory()
    let store = MacroGoalsStore(prefs: PrefStore(db: db))
    if let goals { try store.save(goals) }
    let resolvedCache = try cache ?? OfflineCache(db: AppDatabase.inMemory())
    return EnergyBandService(reader: reader, store: store,
                             cache: resolvedCache,
                             now: { Date(timeIntervalSince1970: 0) }, dayKey: { _ in today })
}

@Test @MainActor func refreshComputesTheBandFromTheUsersTarget() async throws {
    let s = try service(TotalsFake(rows: week), goals: subtract500)
    await s.refresh()
    #expect(s.kcalTarget == 1800)                          // 2300 − 500, typed by the user
    #expect(s.result?.bandLowKcal == 1700)
    #expect(s.result?.bandHighKcal == 1900)
    #expect(s.result?.burnKcal == 2300)
    #expect(s.result?.impliedDeficitKcal == 500)
    #expect(s.result?.settled == true)                     // 17…23 = 7 complete days
    #expect(s.today?.proteinG == 52)
    #expect(s.reasonWord == nil)
}

/// A goal that already includes the deficit is never subtracted again.
@Test @MainActor func includesDeficitGoal1600GivesBand1500To1700() async throws {
    let s = try service(TotalsFake(rows: week), goals: includes1600)
    await s.refresh()
    #expect(s.result?.bandLowKcal == 1500)
    #expect(s.result?.bandHighKcal == 1700)
    #expect(s.result?.impliedDeficitKcal == 700)           // information: 2300 − 1600
}

@Test @MainActor func noGoalMeansNoBandButTheBurnIsStillKnown() async throws {
    let s = try service(TotalsFake(rows: week))
    await s.refresh()
    #expect(s.goals == .unset)
    #expect(s.needsGoal)
    #expect(s.result == nil)
    #expect(s.kcalTarget == nil)
    #expect(s.burnWindow?.burnKcal == 2300)
}

/// The band needs a goal, not Health.
@Test @MainActor func bandExistsWithoutHealth() async throws {
    let s = try service(nil, goals: includes1600)
    await s.refresh()
    #expect(s.result?.bandLowKcal == 1500)
    #expect(s.result?.calibrating == true)
    #expect(s.burnWindow == nil)
    #expect(s.reasonWord == "Not in Health yet")
}

/// Review Focus 2: nothing granted yet → every day nil → "Not in Health yet", no burn, no balance.
@Test @MainActor func noHealthValuesAtAllSaysNotInHealthYet() async throws {
    let s = try service(TotalsFake(rows: (17...24).map { HealthDailyTotals(date: "2026-09-\($0)") }), goals: subtract500)
    await s.refresh()
    #expect(s.result?.burnKcal == nil)
    #expect(s.result?.balanceKcal == nil)
    #expect(s.reasonWord == "Not in Health yet")
}

@Test @MainActor func twoCompleteDaysSaysCalibrating() async throws {
    let rows = (17...24).map { d in HealthDailyTotals(date: "2026-09-\(d)", basalKcal: d >= 22 ? 1800 : nil, activeKcal: 500) }
    let s = try service(TotalsFake(rows: rows), goals: subtract500)
    await s.refresh()
    #expect(s.reasonWord == "Calibrating")
    #expect(s.result?.bandLowKcal == 1700)                 // the band itself does not calibrate
    #expect(s.result?.impliedDeficitKcal == nil)
}

@Test @MainActor func readErrorKeepsTheCachedTotals() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    try cache.put(EnergyBandService.cacheKey, week)
    let s = try service(TotalsFake(rows: [], error: URLError(.unknown)), goals: subtract500, cache: cache)
    await s.refresh()
    #expect(s.result?.burnKcal == 2300)
}

@Test func snapshotGoalsAndCaptions() {
    let snap = NutritionGoalsSnapshot(macros: MacroGoals(kcal: KcalGoal(goalKcal: 1800, basis: .includesDeficit),
                                                         proteinG: 155, carbsG: 144, fatG: 49))
    #expect(snap.goal(for: .protein) == 155)
    #expect(snap.goal(for: .kcal) == 1800)
    #expect(snap.kcalBand.map { [$0.low, $0.high] } == [1700, 1900])
    #expect(snap.goal(for: .hrv) == nil)
    #expect(snap.caption(for: .protein, value: 127) == "/ 155 g")
    #expect(snap.caption(for: .kcal, value: 1750) == "On goal")
    #expect(snap.caption(for: .kcal, value: 1650) == "Under goal")
    #expect(snap.caption(for: .kcal, value: 1950) == "Over goal")
    #expect(snap.caption(for: .kcal, value: nil) == nil)
    #expect(snap.caption(for: .hrv, value: 50) == nil)
}

/// Unset renders "Set your goal", never a number.
@Test func unsetGoalsCaptionSetYourGoal() {
    let partial = NutritionGoalsSnapshot(macros: MacroGoals(proteinG: 160))
    #expect(partial.caption(for: .protein, value: 100) == "/ 160 g")
    #expect(partial.caption(for: .carbs, value: 100) == "Set your goal")
    #expect(partial.caption(for: .kcal, value: 1500) == "Set your goal")
    #expect(partial.kcalBand == nil)
    #expect(partial.goal(for: .fat) == nil)
    #expect(NutritionGoalsSnapshot(macros: .unset).caption(for: .protein, value: nil) == "Set your goal")
    #expect(NutritionGoalsSnapshot.unknown.goal(for: .protein) == nil)
}

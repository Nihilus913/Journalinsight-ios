import Foundation
import Testing
import JICore
import JIFeatures
import JIPersistence
import JISnapshot
@testable import JournalInsight

// B-57 W2 C5 (B-73): the widget macros come from the user's own goals + today's Health food.

private nonisolated struct AppTotalsFake: HealthDailyTotalsProviding {
    func dailyTotals(days: Int) async throws -> [HealthDailyTotals] {
        (17...24).map { HealthDailyTotals(date: "2026-09-\($0)", basalKcal: 1800, activeKcal: 500, dietaryKcal: $0 == 24 ? 650 : 1800,
                                          proteinG: $0 == 24 ? 52 : 150, carbsG: 100, fatG: 40) }
    }
}

@MainActor private func env() throws -> AppEnvironment {
    try AppEnvironment(inMemory: true, snapshotStore: SnapshotStore(suiteName: "test.b73.\(UUID())"))
}

@Test @MainActor func publishedSnapshotCarriesMacrosFromTheUsersGoals() async throws {
    let env = try env()
    // Test values a user typed. JI ships none.
    try env.macroGoals.save(MacroGoals(kcal: KcalGoal(goalKcal: 1800, basis: .includesDeficit), proteinG: 155, carbsG: 144, fatG: 49))
    env.energyBand = EnergyBandService(reader: AppTotalsFake(), store: env.macroGoals, cache: env.cache,
                                       now: { Date() }, dayKey: { _ in "2026-09-24" })
    await env.energyBand?.refresh()
    let macros = try #require(env.currentMacrosSnapshot())
    #expect(macros.kcal?.left == 1150)        // 1800 − 650
    #expect(macros.protein?.left == 103)      // 155 − 52
}

@Test @MainActor func unsetGoalsPublishNoMacros() async throws {
    let env = try env()
    env.energyBand = EnergyBandService(reader: AppTotalsFake(), store: env.macroGoals, cache: env.cache,
                                       now: { Date() }, dayKey: { _ in "2026-09-24" })
    await env.energyBand?.refresh()
    #expect(env.currentMacrosSnapshot() == nil)   // no goal → no "left", never a default
}

/// Review Focus 4: building + refreshing the band never enqueues a hub write.
@Test @MainActor func bandRefreshNeverTouchesTheOutbox() async throws {
    let env = try env()
    try env.macroGoals.save(MacroGoals(kcal: KcalGoal(goalKcal: 1800, basis: .includesDeficit)))
    env.energyBand = EnergyBandService(reader: AppTotalsFake(), store: env.macroGoals, cache: env.cache,
                                       now: { Date() }, dayKey: { _ in "2026-09-24" })
    await env.refreshEnergyBand()
    await env.refreshEnergyBand()
    #expect(env.energyBand?.result?.bandLowKcal == 1700)
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "App/AppEnvironment.swift"), encoding: .utf8)
    #expect(!source.contains("GoalsMirror"))       // the environment has no mirror hook at all
}

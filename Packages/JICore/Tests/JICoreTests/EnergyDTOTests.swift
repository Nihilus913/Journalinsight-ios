import Foundation
import Testing
@testable import JICore

@Test func decodesEnergyReportFromFixture() throws {
    let e = try JSON.decoder.decode(EnergyReport.self, from: fixture("nutrition_energy"))
    #expect(e.trackingDays == 26)
    #expect(e.compliant)
    #expect(!e.days.isEmpty)
    #expect(e.days.allSatisfy { $0.date.count == 10 })
}

/// Regression: a day with no logged intake (`kcal_consumed: null`) must decode to `nil`, never
/// `0` (CLAUDE.md rule 5 — never render a zero for missing data).
@Test func energyDayKeepsUntrackedFieldsNilNotZero() throws {
    let e = try JSON.decoder.decode(EnergyReport.self, from: fixture("nutrition_energy"))
    let untracked = try #require(e.days.first { $0.date == "2026-09-06" })
    #expect(untracked.kcalConsumed == nil)
    #expect(untracked.deficitCorrected == nil)
    #expect(untracked.deficitClass == nil)
    #expect(untracked.tdeeRaw != nil) // TDEE is still known even when intake isn't tracked
}

@Test func decodesGoalsFromFixture() throws {
    let g = try JSON.decoder.decode(Goals.self, from: fixture("planning_goals"))
    #expect(g.weight.targetKg == 75.0)
    #expect(g.strength.contains { $0.exercise == "bench" && $0.targetKg == 100.0 })
    #expect(g.stepsDaily == 15000)
    #expect(g.nutrition.kcalGoal == 1935.0)
}

@Test func mockProviderServesEnergyAndGoals() async throws {
    let provider = MockDataProvider()
    let e = try await provider.energy(windowDays: 7)
    #expect(!e.days.isEmpty)
    let g = try await provider.goals()
    #expect(g.stepsDaily == 15000)
}

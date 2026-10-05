import Testing
import JICore
import JICompute
@testable import JIFeatures

/// RG-46: "What you burn — Not in Health yet" while the hub has the watch's tdee_raw every day.
/// Without a Health burn the card now shows the hub's measured burn, with its own source copy.
@Suite struct RG46EnergyBurnFallbackTests {
    private let days = [
        EnergyDay(date: "2026-10-03", tdeeRaw: 2100, tdeeCorrected: 1900),
        EnergyDay(date: "2026-10-04", tdeeRaw: 2139.5, tdeeCorrected: 1910.1),
        EnergyDay(date: "2026-10-05", tdeeRaw: 900),   // today, partial: never counted
    ]

    @Test func healthBurnWinsWithHealthCopy() {
        let w = EnergyBurnWindow(completeDays: 7, settled: true, burnKcal: 2300, basalKcal: 1700, activeKcal: 600)
        let d = energyBurnCardDisplay(window: w, reason: nil, days: days, today: "2026-10-05")
        #expect(d.kcal == 2300)
        #expect(d.caption == "kcal a day")
        #expect(d.copy == energyBurnCardCopy)
        #expect(!d.fromHub)
    }

    @Test func hubTdeeRawStandsInWhenHealthHasNoBurn() {
        let d = energyBurnCardDisplay(window: nil, reason: "Not in Health yet", days: days, today: "2026-10-05")
        #expect(d.kcal == 2120)   // (2100 + 2139.5) / 2, rounded; today excluded; corrected never used
        #expect(d.caption == "kcal a day")
        #expect(d.fromHub)
        #expect(d.copy == energyBurnCardHubCopy)
        #expect(!d.copy.contains("Apple Health."))
    }

    @Test func noBurnAnywhereKeepsTheReason() {
        let d = energyBurnCardDisplay(window: nil, reason: "Not in Health yet", days: [], today: "2026-10-05")
        #expect(d.kcal == nil)
        #expect(d.caption == "Not in Health yet")
    }
}

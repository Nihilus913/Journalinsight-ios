import Testing
@testable import JIFeatures

/// RG-42: on a 0-meal day the hero numerals rendered a heavy "—" that reads as a stuck skeleton bar,
/// and the YESTERDAY cards lost their titles. A missing hero now draws words, never a dash bar.
@Suite struct RG42MissingHeroTests {
    @Test func nutritionHeroHasNoNumeralWhenKcalMissing() {
        #expect(nutritionHeroNumeral(nil) == nil)
        #expect(nutritionHeroNumeral(1384) == "1384")
    }

    @Test func nutritionGoalTextStandsAloneWhenKcalMissing() {
        #expect(nutritionHeroGoalText(kcal: nil, goal: 1935) == "Goal 1935 kcal")
        #expect(nutritionHeroGoalText(kcal: 1200, goal: 1935) == "/ 1935 kcal")
    }

    @Test func previousDayCardsAlwaysCarryTitles() {
        #expect(nutritionPreviousDayCardTitle("kcal") == "Calories")
        #expect(nutritionPreviousDayCardTitle("g protein") == "Protein")
    }

    @Test func energyHeroHasNoNumeralWithoutBalance() {
        #expect(energyHeroNumeralOrNil(nil) == nil)
        #expect(energyHeroNumeralOrNil(500) == "\u{2212}500")
        #expect(energyHeroMissingText == "No 7-day balance yet")
    }
}

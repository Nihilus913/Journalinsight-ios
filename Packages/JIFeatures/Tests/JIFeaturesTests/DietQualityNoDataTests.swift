import Testing
import JICore
@testable import JIFeatures

/// RG-44 / RG-45 (W-FIX-P2, B-99): a 0-meal day is the no-data state (not "Incomplete · 0 of 3
/// meals", no "Not in the logged food" ×4); protein alone is not scored; the method sheet says
/// "three contributors" while saturated fat is not in the food log.
@Suite struct DietQualityNoDataTests {
    private func contributors(_ sat: Double?) -> [DietQualityDTO.Contributor] {
        [.init(key: "fibre"), .init(key: "sugar"), .init(key: "sat_fat", score: sat), .init(key: "protein", score: 0)]
    }

    @Test func hubNoDataReasonIsTheNoDataState() {
        let row = NutritionDailyRow(date: "2026-10-05", kcalConsumed: 0, proteinG: 0, mealsLogged: 0,
                                    dietQuality: DietQualityDTO(incomplete: true, reason: "no_data", contributors: contributors(nil)))
        let p = dietQualityPresentation(date: "2026-10-05", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.state == .noData)
        #expect(p.rows.isEmpty)
        #expect(p.caption == "No food logged for this day.")
        #expect(!p.headline.contains("0 of 3"))
    }

    @Test func zeroMealRowWithoutHubScoreIsNoData() {
        let row = NutritionDailyRow(date: "2026-10-05", kcalConsumed: 0, proteinG: 0, mealsLogged: 0)
        let p = dietQualityPresentation(date: "2026-10-05", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.state == .noData)
    }

    @Test func proteinOnlyLineNamesTheMissingFoodDetail() {
        let row = NutritionDailyRow(date: "2026-09-21", kcalConsumed: 1800, proteinG: 140, mealsLogged: 3,
                                    dietQuality: DietQualityDTO(incomplete: true, reason: "no_contributors",
                                                                contributors: contributors(nil)))
        let p = dietQualityPresentation(date: "2026-09-21", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.score == nil)
        #expect(p.state == .incomplete("Incomplete day · no fibre, sugar or saturated-fat detail"))
    }

    @Test func methodSheetSaysThreeContributorsWithoutSatFat() {
        let row = NutritionDailyRow(date: "2026-09-28", kcalConsumed: 1800, proteinG: 150, mealsLogged: 3,
                                    fiberG: 18, sugarG: 40, satFatG: nil,
                                    dietQuality: DietQualityDTO(score: 70, incomplete: false, contributors: contributors(nil)))
        let p = dietQualityPresentation(date: "2026-09-28", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.satFatInData == false)
        let steps = dietQualityMethodSteps(satFatInData: p.satFatInData)
        #expect(steps[0].title == "Three contributors, 0–100 each")
        #expect(!steps.map(\.body).joined().contains("fibre, sugar and saturated-fat detail"))
    }

    @Test func methodSheetSaysFourContributorsWithSatFat() {
        let row = NutritionDailyRow(date: "2026-09-28", kcalConsumed: 1800, proteinG: 150, mealsLogged: 3,
                                    fiberG: 18, sugarG: 40, satFatG: 20,
                                    dietQuality: DietQualityDTO(score: 70, incomplete: false, contributors: contributors(90)))
        let p = dietQualityPresentation(date: "2026-09-28", hubRow: row, health: nil, proteinGoal: 150, kcalGoal: 1935)
        #expect(p.satFatInData)
        #expect(dietQualityMethodSteps(satFatInData: true)[0].title == "Four contributors, 0–100 each")
    }
}

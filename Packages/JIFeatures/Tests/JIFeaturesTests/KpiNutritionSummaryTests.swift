import Testing
import JICore
@testable import JIFeatures

struct KpiNutritionSummaryTests {
    private let rows = (1...30).map { d in
        NutritionDailyRow(date: String(format: "2026-08-%02d", d), kcalConsumed: d == 30 ? nil : 1600, kcalGoal: nil,
                          proteinG: Double(100 + d), carbsG: nil, fatG: 50, mealsLogged: 3)
    }

    @Test func latestIsTheNewestNonNilDay() {
        let s = kpiMacroSummary(rows: rows, macro: .kcal)
        #expect(s.latestDate == "2026-08-29")
        #expect(s.latest == 1600)
    }

    @Test func averagesSkipMissingDays() {
        let s = kpiMacroSummary(rows: rows, macro: .protein)
        #expect(s.avg7 == (124 + 125 + 126 + 127 + 128 + 129 + 130) / 7.0)
        #expect(kpiMacroSummary(rows: rows, macro: .carbs).avg7 == nil)
    }

    @Test func onlyTheFourMacrosAreNutritionKpis() {
        #expect(isNutritionKpi(.protein))
        #expect(!isNutritionKpi(.hrv))
    }
}

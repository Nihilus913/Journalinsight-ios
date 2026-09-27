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

extension KpiNutritionSummaryTests {
    /// Rule 5: goal (W2) and missing actuals read "— No data" in the macro table, never a bare dash.
    @Test func macroTableCellsNeverShowABareDash() {
        let s = KpiMacroSummary(latestDate: "2026-09-22", latest: 127, avg7: nil, avg28: 131.4)
        #expect(kpiMacroTableCells(s, decimals: 0) == ["Set your goal", "127", "— No data", "131"])
    }
}

extension KpiNutritionSummaryTests {
    /// Board: the day column is headed by that day ("22 SEP"); when the macros' newest days differ
    /// the header falls back to "Latest" rather than naming a day some cells are not from.
    @Test func dayColumnHeaderIsTheSharedLatestDay() {
        let a = KpiMacroSummary(latestDate: "2026-09-22", latest: 1, avg7: nil, avg28: nil)
        let b = KpiMacroSummary(latestDate: "2026-09-21", latest: 1, avg7: nil, avg28: nil)
        let none = KpiMacroSummary(latestDate: nil, latest: nil, avg7: nil, avg28: nil)
        #expect(kpiMacroDayHeader([a, a, none]) == "22 SEP")
        #expect(kpiMacroDayHeader([a, b]) == "LATEST")
        #expect(kpiMacroDayHeader([none]) == "LATEST")
    }
}

extension KpiNutritionSummaryTests {
    /// Board: grams carry their unit in the table ("127 g"); calories stay bare; a gap is still
    /// "— No data" whole (the table lays it out on one line, it is never shortened to "—").
    @Test func macroTableCellsCarryTheBoardsUnits() {
        let s = KpiMacroSummary(latestDate: "2026-09-22", latest: 127, avg7: nil, avg28: 131.4)
        #expect(kpiMacroTableCells(s, decimals: 0, unit: kpiMacroTableUnit(.protein)) == ["Set your goal", "127 g", "— No data", "131 g"])
        #expect(kpiMacroTableUnit(.kcal) == nil)
    }
}

// W-FIX5 L5 — R3 (mockup 22): per-day bars from zero and the board's two chevron rows.
extension KpiNutritionSummaryTests {
    @Test func perDayPointsAreTheLastSevenRowDatesNewestLast() {
        let pts = kpiMacroDayPoints(rows: rows, macro: .kcal)
        #expect(pts.count == 7)
        #expect(pts.map(\.id) == (24...30).map { String(format: "2026-08-%02d", $0) })
        #expect(pts.last?.isLatest == true && pts.dropLast().allSatisfy { !$0.isLatest })
        // The 30th has no kcal → nil + "No data" (rule 5), never a zero bar.
        #expect(pts.last?.value == nil && pts.last?.missingReason == .noData)
        #expect(pts.first?.value == 1600)
        #expect(pts.first?.label == "Mon")   // 2026-08-24 is a Monday
        #expect(kpiMacroDayPoints(rows: [], macro: .protein).isEmpty)
    }

    @Test func linkRowsCarryTheBoardsSecondLine() {
        #expect(kpiNutritionLinkSubtitle(.widget, metricLabel: "Protein") == "Small · protein today")
        #expect(kpiNutritionLinkSubtitle(.macroGoals, metricLabel: "Protein") == "Goals setup")
    }

    /// The gallery preview's band: its 28 fixture days against the fixture's own "today" give a
    /// normal (n ≥ 14 in today−34 … today−7), so the sweep cell shows the band, not "Calibrating".
    @Test func previewFixtureHasItsBandAgainstItsOwnToday() {
        let fixture = (1...28).map { d in
            NutritionDailyRow(date: String(format: "2026-08-%02d", d), proteinG: 110 + Double(d), mealsLogged: 3)
        }
        #expect(kpiMacroNormal(rows: fixture, macro: .protein, today: "2026-08-29") != nil)
    }
}

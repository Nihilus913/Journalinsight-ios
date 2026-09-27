import Foundation
import Testing
import JICore
import JIDesign
@testable import JIFeatures

/// W-FIX5 L5 guards (pass on the base): what R3 (KPI detail nutrition) and X2 (state faces)
/// must keep — the W3-H3 band, BUG-40's bar-not-line rule, the ScreenState resolution.
struct Fix5L5GuardTests {
    private let rows: [NutritionDailyRow] = (1...28).map { d in
        NutritionDailyRow(date: String(format: "2026-08-%02d", d), kcalConsumed: 1550 + Double(d * 5), kcalGoal: nil,
                          proteinG: 110 + Double(d), carbsG: nil, fatG: 48 + Double(d % 6), mealsLogged: 3)
    }

    /// W3-H3 (fixed 03fbfa4): the macro NormalBar has the 28-day personal normal once 14 logged
    /// days sit in today−34 … today−7 — and stays "Calibrating" (nil) when they do not.
    @Test func nutritionNormalBandExistsWithEnoughLoggedDays() {
        #expect(kpiMacroNormal(rows: rows, macro: .protein, today: "2026-08-29") != nil)
        #expect(kpiMacroNormal(rows: rows, macro: .carbs, today: "2026-08-29") == nil)
        #expect(kpiMacroNormal(rows: rows, macro: .protein, today: "2026-12-01") == nil)
    }

    /// BUG-40: nutrition KPIs never draw the smoothed line trend.
    @Test func nutritionKpisNeverShowTheLineTrend() {
        #expect(!kpiDetailShowsLineTrend(.protein))
        #expect(kpiDetailShowsLineTrend(.hrv))
    }

    /// The board's two closing rows, in board order.
    @Test func nutritionLinksAreWidgetThenGoals() {
        #expect(KpiNutritionLink.allCases.map(\.title) == ["Put on a widget", "Edit macro goals"])
    }

    /// DESIGN-7: the state faces are resolved from the same signals `TodayViewModel` tracks.
    @Test func screenStateResolutionIsUnchanged() {
        #expect(ScreenState.resolve(phase: .empty, neverSynced: true, verdictDate: nil, todayDateString: "2026-09-27", lastError: nil) == .neverSynced)
        #expect(ScreenState.resolve(phase: .loaded, neverSynced: false, verdictDate: "2026-09-26", todayDateString: "2026-09-27", lastError: nil) == .staleVerdictDate("2026-09-26"))
        #expect(ScreenState.resolve(phase: .error("boom"), neverSynced: false, verdictDate: nil, todayDateString: "2026-09-27", lastError: nil) == .error("boom"))
    }
}

import SwiftUI
import Testing
@testable import JIDesign

@Suite struct TrendRowMathTests {
    @Test func aMissingSideOrAZeroBaselineHasNoDirection() {
        #expect(trendDirection(recent: nil, baseline: 50) == .unknown)
        #expect(trendDirection(recent: 50, baseline: nil) == .unknown)
        #expect(trendDirection(recent: nil, baseline: nil) == .unknown)
        #expect(trendDirection(recent: 50, baseline: 0) == .unknown)
    }

    @Test func aChangeInsideTheToleranceBandReadsFlatNotAsADirection() {
        #expect(trendDirection(recent: 50.5, baseline: 50) == .flat)     // +1 %
        #expect(trendDirection(recent: 49.5, baseline: 50) == .flat)     // −1 %
        #expect(trendDirection(recent: 50, baseline: 50) == .flat)
    }

    @Test func aRealMoveReadsUpOrDown() {
        #expect(trendDirection(recent: 55, baseline: 50) == .up)         // +10 %
        #expect(trendDirection(recent: 45, baseline: 50) == .down)       // −10 %
    }

    @Test func theToleranceIsCallerTunable() {
        #expect(trendDirection(recent: 55, baseline: 50, tolerance: 0.2) == .flat)
        #expect(trendDirection(recent: 50.5, baseline: 50, tolerance: 0.001) == .up)
    }

    /// A negative baseline (kcal deficit) still compares by magnitude, never flipping the sign.
    @Test func aNegativeBaselineComparesByMagnitude() {
        #expect(trendDirection(recent: -400, baseline: -500) == .up)
        #expect(trendDirection(recent: -600, baseline: -500) == .down)
    }

    @Test func everyDirectionHasItsOwnGlyphAndSpokenName() {
        let symbols = Set(JITrendDirection.allCases.map(\.symbolName))
        #expect(symbols.count == JITrendDirection.allCases.count)
        let spoken = Set(JITrendDirection.allCases.map(\.spokenName))
        #expect(spoken.count == JITrendDirection.allCases.count)
    }

    @Test func theValueTextPairsTheTwoAveragesAndCarriesTheUnitOnce() {
        #expect(trendValueText(recent: 52, baseline: 49, unit: "ms") == "52 vs 49 ms")
        #expect(trendValueText(recent: 1.24, baseline: 1.05, unit: nil, decimals: 2) == "1.24 vs 1.05")
    }

    /// Rule 5: a missing average is an em dash, never a zero — and a wholly empty row drops the
    /// dangling unit, like `StatChip` does.
    @Test func aMissingAverageIsAnEmDashAndAnEmptyRowDropsTheUnit() {
        #expect(trendValueText(recent: nil, baseline: 49, unit: "ms") == "— vs 49 ms")
        #expect(trendValueText(recent: nil, baseline: nil, unit: "ms") == "— vs —")
    }

    @Test func theRowSpeaksBothAveragesAndTheDirection() {
        let label = trendRowAccessibilityLabel(name: "HRV", recent: 52, baseline: 49, unit: "ms", decimals: 0, direction: .up)
        #expect(label.contains("HRV"))
        #expect(label.contains("52 vs 49 ms"))
        #expect(label.contains("trending up"))
    }
}

@Test @MainActor func trendRowRenders() {
    expectRenders("TrendRow", width: 180, height: 60) { TrendRow(name: "HRV", recent: 52, baseline: 49, unit: "ms", tint: .purple) }
    expectRenders("TrendRow no data", width: 180, height: 60) { TrendRow(name: "Weight", recent: nil, baseline: nil, unit: "kg", decimals: 1, tint: .purple) }
}

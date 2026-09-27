import SwiftUI
import Testing
@testable import JIDesign

// W-GUI S1 — the square sparkline carries its scale words and its last value.
@Test func sparklineAxisWordsNameTheWindow() {
    #expect(sparklineAxisWords(count: 14).start == "13d ago" && sparklineAxisWords(count: 14).end == "today")
    #expect(sparklineAxisWords(count: 7).start == "6d ago")
    #expect(sparklineAxisWords(count: 1).start == "today")
}

@Test func sparklineLastValueSkipsMissingDays() {
    #expect(sparklineLastValue([48, 50, nil]) == 50)
    #expect(sparklineLastValue([nil, nil]) == nil)
}

@Test @MainActor func sparklineRendersWithAndWithoutABand() {
    expectRenders("NormalSparkline band", width: 160, height: 60) {
        NormalSparkline(points: [48, 50, 47, 53, nil, 49, 52], normal: 46...52, tint: .hrv, unit: "ms")
    }
    expectRenders("NormalSparkline calibrating", width: 160, height: 60) {
        NormalSparkline(points: [48, 50, 47, 53, 51, 49, 52], tint: .hrv, unit: "ms")
    }
    expectRenders("NormalSparkline one point", width: 160, height: 60) { NormalSparkline(points: [48]) }
}

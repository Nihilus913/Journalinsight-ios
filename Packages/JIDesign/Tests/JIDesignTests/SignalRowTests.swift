import SwiftUI
import Testing
@testable import JIDesign

struct SignalRowTests {
    @Test func referencePrefersNormalThenGoalThenDetail() {
        #expect(signalReferenceText(normal: 27...30, goal: 7, unit: "ms", decimals: 0, detail: "x") == "your normal 27–30")
        #expect(signalReferenceText(normal: nil, goal: 155, unit: "g", decimals: 0, detail: "x") == "goal 155 g")
        #expect(signalReferenceText(normal: nil, goal: nil, unit: "h", decimals: 1, detail: "floor 7.0 h") == "floor 7.0 h")
        #expect(signalReferenceText(normal: nil, goal: nil, unit: nil, decimals: 0, detail: nil) == nil)
    }

    @Test func accessibilityIsWordsWithStatusAndReference() {
        #expect(signalRowAccessibilityLabel(label: "Overnight HRV", value: 25, unit: "ms", decimals: 0, status: .watch, reference: "threshold 27 ms")
                == "Overnight HRV, 25 ms, Watch, threshold 27 ms")
        #expect(signalRowAccessibilityLabel(label: "Resting HR", value: nil, unit: "bpm", decimals: 0, status: .missing(.noData), reference: nil)
                == "Resting HR, no value, No data")
    }

    @Test @MainActor func renders() {
        expectRenders("SignalRow", height: 80) { SignalRow(label: "Overnight HRV", value: 25, unit: "ms", status: .watch, detail: "threshold 27 ms") }
        expectRenders("SignalRow missing", height: 80) { SignalRow(label: "Resting HR", value: nil, unit: "bpm", status: .missing(.noData)) }
    }
}

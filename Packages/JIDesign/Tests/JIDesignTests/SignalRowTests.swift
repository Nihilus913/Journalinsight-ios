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

    /// Verifier W-B57-W1: at AX3 a height-starved parent squeezed the row until its lines overlapped
    /// the next row. The row must keep its full height whatever height it is offered.
    @Test @MainActor func rowKeepsItsFullHeightAtAX3WhenOfferedLess() throws {
        func height(_ proposed: CGFloat?) throws -> CGFloat {
            let r = ImageRenderer(content: SignalRow(label: "HRV (7-day)", value: 46, unit: "ms", status: .watch, detail: "threshold 41 ms")
                .environment(\.dynamicTypeSize, .accessibility3))
            r.proposedSize = ProposedViewSize(width: 300, height: proposed)
            return CGFloat(try #require(r.cgImage).height) / r.scale
        }
        let ideal = try height(nil)
        #expect(ideal > 44, "label + reference + value + status need more than the 44 pt floor")
        #expect(try height(40) >= ideal)
    }

    @Test @MainActor func renders() {
        expectRenders("SignalRow", height: 80) { SignalRow(label: "Overnight HRV", value: 25, unit: "ms", status: .watch, detail: "threshold 27 ms") }
        expectRenders("SignalRow missing", height: 80) { SignalRow(label: "Resting HR", value: nil, unit: "bpm", status: .missing(.noData)) }
    }
}

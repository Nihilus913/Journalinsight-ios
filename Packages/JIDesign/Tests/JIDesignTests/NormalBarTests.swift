import SwiftUI
import Testing
@testable import JIDesign

// B-57 §1 NormalBar: fill = 7-day value, shaded = 28-day normal, white tick = median, amber tick = goal.
struct NormalBarTests {
    @Test func geometryScalesEveryMarkOnOneAxisWithHeadroom() throws {
        let g = try #require(normalBarGeometry(value: 100, normal: 80...120, median: 96, goal: 160))
        // top = 160 → scale 200
        #expect(g.fill == 0.5)
        #expect(g.bandLower == 0.4)
        #expect(g.bandUpper == 0.6)
        #expect(g.median == 0.48)
        #expect(g.goal == 0.8)
    }

    @Test func nothingToDrawIsNilNeverAZeroBar() {
        #expect(normalBarGeometry(value: nil, normal: nil, median: nil, goal: nil) == nil)
        #expect(normalBarGeometry(value: 0, normal: nil, median: nil, goal: nil) == nil)
    }

    @Test func missingValueKeepsTheBandButNoFill() throws {
        let g = try #require(normalBarGeometry(value: nil, normal: 27...30, median: 28, goal: nil))
        #expect(g.fill == nil)
        #expect(g.bandUpper != nil)
    }

    @Test func noNormalCaptionSaysCalibrating() {
        #expect(normalBarCaption(normal: nil, median: nil, decimals: 0) == "normal — Calibrating")
        #expect(normalBarCaption(normal: 27...30, median: 28, decimals: 0) == "normal 27–30 · median 28")
    }

    @Test func accessibilityValueIsWords() {
        #expect(normalBarAccessibilityValue(value: 25, normal: nil, median: nil, goal: nil, unit: "ms", decimals: 0)
                == "7 day value 25 ms, your normal still calibrating")
        #expect(normalBarAccessibilityValue(value: nil, normal: 27...30, median: 28, goal: 155, unit: "g", decimals: 0)
                == "7 day value, no data, your normal 27 to 30, median 28, goal 155 g")
    }

    @Test func legendIsTheBoardWording() {
        #expect(normalBarLegendText == "fill = 7 days · shaded = your normal · median")
    }

    @Test @MainActor func rendersWithAndWithoutData() {
        expectRenders("NormalBar full") { NormalBar(value: 127, normal: 120...150, median: 135, goal: 155, unit: "g", tint: .info) }
        expectRenders("NormalBar calibrating") { NormalBar(value: 25, normal: nil, unit: "ms") }
        expectRenders("NormalBar empty") { NormalBar(value: nil, normal: nil) }
        expectRenders("NormalBarLegend") { NormalBarLegend() }
    }
}

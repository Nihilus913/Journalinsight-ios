import SwiftUI
import Testing
@testable import JIDesign

struct SquareGridTests {
    private let hrv = JISquareItem(id: "hrv", label: "HRV", systemImage: "waveform.path.ecg", tint: .info, value: 25, unit: "ms", status: .watch, badge: .hide)
    private let rhr = JISquareItem(id: "rhr", label: "Resting HR", value: nil, status: .missing(.noData), badge: .hide)
    private let kcal = JISquareItem(id: "kcal", label: "Calories", value: 1619, unit: "kcal", goalText: "/ —", badge: .add)

    @Test func moveInsertsBeforeTheTarget() {
        #expect(squareGridMove(["a", "b", "c", "d"], moving: "d", before: "b") == ["a", "d", "b", "c"])
        #expect(squareGridMove(["a", "b", "c"], moving: "a", before: "c") == ["b", "a", "c"])
        #expect(squareGridMove(["a", "b"], moving: "a", before: "a") == ["a", "b"])
        #expect(squareGridMove(["a", "b"], moving: "x", before: "a") == ["a", "b"])   // unknown id = no-op
    }

    @Test func squareGridDropsToTwoColumnsAtAXSizes() {
        #expect(squareGridColumnCount(isAccessibilitySize: false) == 3)
        #expect(squareGridColumnCount(isAccessibilitySize: true) == 2)
    }

    @Test func accessibilityLabelSpellsValueStatusAndBadge() {
        #expect(squareAccessibilityLabel(hrv) == "HRV, 25 ms, Watch")
        #expect(squareAccessibilityLabel(rhr) == "Resting HR, no value, No data")
        #expect(squareAccessibilityLabel(kcal) == "Calories, 1619 kcal / —")
        #expect(squareBadgeActionLabel(hrv) == "Hide HRV")
        #expect(squareBadgeActionLabel(kcal) == "Add Calories")
        #expect(squareBadgeActionLabel(JISquareItem(id: "s", label: "Steps", value: nil, badge: .selected)) == "Remove Steps from Today")
        #expect(squareBadgeActionLabel(JISquareItem(id: "s", label: "Steps", value: nil)) == nil)
    }

    @Test @MainActor func renders() {
        expectRenders("SquareGrid", height: 320) { SquareGrid(items: [hrv, rhr, kcal]) }
        expectRenders("SquareGrid editing", height: 320) { SquareGrid(items: [hrv, rhr], editing: true, onBadge: { _ in }, onMove: { _, _ in }, onAdd: {}) }
        expectRenders("SquareGrid empty", height: 120) { SquareGrid(items: [], editing: true, onAdd: {}) }
    }
}

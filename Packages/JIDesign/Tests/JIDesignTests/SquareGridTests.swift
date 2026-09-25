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
        #expect(squareGridColumnCount(preferred: 2, isAccessibilitySize: false) == 2)
        #expect(squareGridColumnCount(preferred: 3, isAccessibilitySize: true) == 2)
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

    /// W-FIX3 BUG-33 (R4-09): at AX sizes the icon sits above the label so the label gets the
    /// square's full width and "Resting" never hyphenates to "Rest-/ing".
    @Test func iconStacksAboveTheLabelOnlyAtAXSizes() {
        #expect(squareLabelStacksIcon(isAccessibilitySize: true))
        #expect(!squareLabelStacksIcon(isAccessibilitySize: false))
    }

    /// W-FIX3 BUG-33 (R1-19): the badge glyph is sized from the (scaled) circle, so the "−" never
    /// overflows its badge at AX3.
    @Test func badgeGlyphTracksTheCircle() {
        #expect(squareBadgeGlyphPointSize(side: 24) == 12)
        #expect(squareBadgeGlyphPointSize(side: 40) == 20)
        #expect(squareBadgeGlyphPointSize(side: 60) < 60)
    }

    /// The badge grows a little with the type size but stays a corner badge (24…32 pt), never a
    /// 60-pt disc over the square's icon at AX3.
    @Test func badgeSideIsClamped() {
        #expect(squareBadgeSide(scaled: 24) == 24)
        #expect(squareBadgeSide(scaled: 28) == 28)
        #expect(squareBadgeSide(scaled: 60) == 32)
        #expect(squareBadgeSide(scaled: 18) == 24)
    }

    /// W-FIX4 BUG-19 (EditToday − badge): the badge is hosted ABOVE the square's drag source and
    /// its tap shape — never inside `.draggable` / `.contentShape(Rectangle())`, where the drag
    /// interaction and the clipped hit area swallowed the "−" tap in the editing branch.
    @Test func badgeSitsAboveTheDragSourceInEveryBranch() {
        #expect(squareBadgeHost(editing: true, draggable: true) == .aboveDragSource)
        #expect(squareBadgeHost(editing: true, draggable: false) == .aboveDragSource)
        #expect(squareBadgeHost(editing: false, draggable: false) == .aboveDragSource)
    }

    /// The badge's whole circle is tappable: its hit target is at least 44 pt (HIG) and centred on
    /// the drawn circle, which straddles the square's top-leading corner.
    @Test func badgeHitTargetIsAtLeast44Points() {
        #expect(squareBadgeHitSide(side: 24) >= 44)
        #expect(squareBadgeHitSide(side: 32) >= 44)
        #expect(squareBadgeHitSide(side: 50) == 50)
    }

    @Test @MainActor func rendersAtAX3() {
        expectRenders("SquareGrid AX3", height: 480) {
            SquareGrid(items: [hrv, rhr], editing: true, columns: 2, onBadge: { _ in }, onMove: { _, _ in }, onAdd: {})
                .environment(\.dynamicTypeSize, .accessibility3)
        }
    }

    @Test @MainActor func renders() {
        expectRenders("SquareGrid", height: 320) { SquareGrid(items: [hrv, rhr, kcal]) }
        expectRenders("SquareGrid editing", height: 320) { SquareGrid(items: [hrv, rhr], editing: true, onBadge: { _ in }, onMove: { _, _ in }, onAdd: {}) }
        expectRenders("SquareGrid empty", height: 120) { SquareGrid(items: [], editing: true, onAdd: {}) }
    }
}

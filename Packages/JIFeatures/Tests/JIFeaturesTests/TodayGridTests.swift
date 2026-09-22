import Foundation
import SwiftUI
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

@Test func tileOrderPersistsAcrossRelaunch() throws {
    let db = try AppDatabase.inMemory()
    let chipIDs = ["hrv", "rhr", "sleep", "steps"]

    // "Session 1": grid loads the default order (nothing persisted yet) and the user reorders it.
    let firstPrefs = PrefStore(db: db)
    let initialOrder = loadTileOrder(prefs: firstPrefs, chipIDs: chipIDs)
    #expect(initialOrder == chipIDs)
    let reordered = ["steps", "hrv", "rhr", "sleep"]
    saveTileOrder(reordered, prefs: firstPrefs)

    // "Relaunch": a fresh PrefStore/grid over the SAME underlying database re-reads the order.
    let freshPrefs = PrefStore(db: db)
    let restored = loadTileOrder(prefs: freshPrefs, chipIDs: chipIDs)
    #expect(restored == reordered)
}

@Test @MainActor func tileOrderResolvesThroughAFreshViewModel() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let db = try AppDatabase.inMemory()
    let prefs = PrefStore(db: db)
    try prefs.set(todayTileOrderKey, ["steps", "sleep", "rhr", "hrv"])

    let vm = TodayViewModel(provider: MockDataProvider(), cache: cache, prefs: PrefStore(db: db))
    let order = loadTileOrder(prefs: vm.tileOrderStore, chipIDs: ["hrv", "rhr", "sleep", "steps"])
    #expect(order == ["steps", "sleep", "rhr", "hrv"])
}

@Test func unknownPersistedIdsAreDroppedAndNewChipsAreAppended() {
    let resolved = resolveTileOrder(chipIDs: ["hrv", "rhr", "sleep", "steps"], savedOrder: ["ghost", "steps", "hrv"])
    #expect(resolved == ["steps", "hrv", "rhr", "sleep"])
}

@Test func missingPrefsFallsBackToDefaultOrderWithoutCrashing() {
    let order = loadTileOrder(prefs: nil, chipIDs: ["hrv", "rhr", "sleep", "steps"])
    #expect(order == ["hrv", "rhr", "sleep", "steps"])
}

@Test func reduceMotionSuppressesJiggle() {
    #expect(jiggleEnabled(isReordering: true, reduceMotion: false))
    #expect(jiggleEnabled(isReordering: true, reduceMotion: true) == false)
    #expect(jiggleEnabled(isReordering: false, reduceMotion: false) == false)
    #expect(jiggleEnabled(isReordering: false, reduceMotion: true) == false)
}

@Test func chipActionInvokesOnSelectKpiWithThatChipsId() {
    var selected: [String] = []
    let hrvAction = chipTapAction(id: "hrv", onSelectKpi: { selected.append($0) })
    let stepsAction = chipTapAction(id: "steps", onSelectKpi: { selected.append($0) })

    hrvAction()
    stepsAction()
    hrvAction()

    #expect(selected == ["hrv", "steps", "hrv"])
}

/// W4-L2 (P-mind): the Today Mind tile pushes `MindView` — exercised at the pure tap-seam level
/// (mirrors `chipActionInvokesOnSelectKpiWithThatChipsId` above), since `TodayGrid`'s
/// `.navigationDestination` itself needs a `NavigationStack`/rendering harness this test target
/// doesn't have.
@Test func mindTileActionInvokesOnOpenMind() {
    var opened = 0
    let action = mindTileTapAction(onOpenMind: { opened += 1 })
    action()
    action()
    #expect(opened == 2)
}

// W-B47 L2 (P-today): the Fitness 2-up card grid replaces W9.5-L4's width-driven `.adaptive`
// columns. Two columns at compact width, three at regular, one at an accessibility type size.
@Test func todayCardGridIsTwoUpCompactAndThreeUpRegular() {
    #expect(todayCardColumnCount(horizontalSizeClass: .compact, isAccessibilitySize: false) == 2)
    #expect(todayCardColumnCount(horizontalSizeClass: nil, isAccessibilitySize: false) == 2)
    #expect(todayCardColumnCount(horizontalSizeClass: .regular, isAccessibilitySize: false) == 3)
}

/// B-33 §8.1 "reflows, never clips": a 20 pt bold card title cannot share a 393 pt screen at an
/// accessibility size, so the grid drops to one column rather than truncating both titles.
@Test func anAccessibilityTypeSizeCollapsesTheCardGridToOneColumn() {
    #expect(todayCardColumnCount(horizontalSizeClass: .compact, isAccessibilitySize: true) == 1)
    #expect(todayCardColumnCount(horizontalSizeClass: .regular, isAccessibilitySize: true) == 1)
}

@Test func todayCardGridColumnsAreEqualWidthFlexibleItems() {
    let compact = todayCardGridColumns(horizontalSizeClass: .compact, isAccessibilitySize: false)
    let regular = todayCardGridColumns(horizontalSizeClass: .regular, isAccessibilitySize: false)
    let ax = todayCardGridColumns(horizontalSizeClass: .compact, isAccessibilitySize: true)
    #expect(compact.count == 2)
    #expect(regular.count == 3)
    #expect(ax.count == 1)
    for item in compact + regular + ax {
        if case .flexible = item.size {} else { Issue.record("Today cards must be equal-width .flexible columns, not .adaptive") }
        #expect(item.spacing == todayGridSpacing)
    }
}

// MARK: - chip -> Fitness summary card

@Test func everyTodayChipMapsToACardWithAnIconATintAndAFormattedValue() {
    let hrv = todaySummaryCardSpec(for: TodayChip(id: "hrv", label: "HRV", value: 61, unit: "ms", points: [58, 61], sourceMissing: false))
    #expect(hrv.icon == "waveform.path.ecg")
    #expect(hrv.title == "HRV")
    #expect(hrv.value == "61")
    #expect(hrv.unit == "ms")
    #expect(hrv.sparkline == [58, 61])

    // One decimal only when the number actually has one (the StatChip rule, carried over).
    #expect(todayCardValueText(7.4, sourceMissing: false) == "7.4")
    // Grouping is the current locale's job — assert the precision rule, not a literal separator.
    #expect(todayCardValueText(8420, sourceMissing: false) == 8420.0.formatted(.number.precision(.fractionLength(0))))
}

/// Rule 5: a source that cannot produce this metric shows the shared copy, never a zero and never
/// a bare dash with a dangling unit.
@Test func aSourceMissingChipCarriesNoValueAndNoUnit() {
    let spec = todaySummaryCardSpec(for: TodayChip(id: "hrv", label: "HRV", value: nil, unit: "ms", points: [], sourceMissing: true))
    #expect(spec.value == nil)
    #expect(spec.unit == nil)
    #expect(spec.sourceMissing)
    #expect(spec.timestamp == nil)
    #expect(todayCardValueText(61, sourceMissing: true) == nil)
}

/// W-B47 integrate: the seam now forwards to L1's `metricTintRole(_:)` — no more neutral stub.
@Test func theMetricTintSeamForwardsToMetricTintRole() {
    #expect(todayCardTintRole("hrv") == .info)
    #expect(todayCardTintRole("steps") == .go)
}

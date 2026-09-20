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

// W9.5-L4 (P-today): rotation — the grid's columns are width-driven (`.adaptive(minimum:)`)
// with the minimum tile width picked per size class, so landscape / iPad get 3+ columns while
// a portrait phone keeps the RN oracle's 2.
@Test func todayGridColumnsAreAdaptiveNotFixed() {
    let compact = todayGridColumns(horizontalSizeClass: .compact)
    let regular = todayGridColumns(horizontalSizeClass: .regular)
    let unknown = todayGridColumns(horizontalSizeClass: nil)
    #expect(compact.count == 1)
    #expect(regular.count == 1)
    #expect(unknown.count == 1)
    if case .adaptive(let min, _) = compact[0].size { #expect(min == todayGridMinimumTileWidth(horizontalSizeClass: .compact)) } else { Issue.record("compact columns must be .adaptive") }
    if case .adaptive(let min, _) = regular[0].size { #expect(min == todayGridMinimumTileWidth(horizontalSizeClass: .regular)) } else { Issue.record("regular columns must be .adaptive") }
}

@Test func todayGridColumnCountGrowsWithWidth() {
    let min = todayGridMinimumTileWidth(horizontalSizeClass: .compact)
    // iPhone 18 Pro portrait: 402pt − 2×16 padding.
    #expect(todayGridColumnCount(availableWidth: 402 - 32, minimumTileWidth: min) == 2)
    // iPhone SE-class portrait.
    #expect(todayGridColumnCount(availableWidth: 375 - 32, minimumTileWidth: min) == 2)
    // iPhone 18 Pro landscape: 874pt − 2×59 safe area − 2×16 padding.
    #expect(todayGridColumnCount(availableWidth: 874 - 118 - 32, minimumTileWidth: min) >= 3)
    // Regular width (iPad / Max landscape) still lands on 3+.
    let regularMin = todayGridMinimumTileWidth(horizontalSizeClass: .regular)
    #expect(todayGridColumnCount(availableWidth: 820 - 32, minimumTileWidth: regularMin) >= 3)
    // Never zero, even when the width is narrower than one tile.
    #expect(todayGridColumnCount(availableWidth: 100, minimumTileWidth: min) == 1)
}

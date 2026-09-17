import Foundation
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

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W5a-L3 (P-edit-today). Ports `mobile/__tests__/data/todayTilePrefs.test.ts` +
// `components/todayTileRegistry.test.ts` onto the Swift tile set (hrv/rhr/sleep/steps).

private let ids = ["hrv", "rhr", "sleep", "steps"]

// MARK: registry (todayTileRegistry.test.ts)

@Test func registryListsEveryTodayChipId() {
    // TodayViewModel.chips is the fixed hrv/rhr/sleep/steps set (TodayViewModel.swift L112–115).
    #expect(TodayTileRegistry.ids == ids)
    for id in TodayTileRegistry.ids { #expect(TodayTileRegistry.label(for: id).isEmpty == false) }
}

@Test @MainActor func registryMatchesLiveViewModelChips() async throws {
    let vm = TodayViewModel(provider: FlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.chips.map(\.id) == TodayTileRegistry.ids)
    #expect(vm.chips.map(\.label) == TodayTileRegistry.ids.map { TodayTileRegistry.label(for: $0) })
}

// MARK: pure prefs ops (todayTilePrefs.test.ts)

@Test func defaultPrefsAreRegistryOrderWithNothingHidden() {
    let p = TodayTilePrefs.default
    #expect(p.order == ids)
    #expect(p.hidden.isEmpty)
}

@Test func moveSwapsOneSlotAndIsANoOpAtTheEnds() {
    let p = TodayTilePrefs.default
    #expect(moveTodayTile(p, id: "rhr", direction: -1).order == ["rhr", "hrv", "sleep", "steps"])
    #expect(moveTodayTile(p, id: "rhr", direction: 1).order == ["hrv", "sleep", "rhr", "steps"])
    #expect(moveTodayTile(p, id: "hrv", direction: -1) == p)
    #expect(moveTodayTile(p, id: "steps", direction: 1) == p)
    #expect(moveTodayTile(p, id: "ghost", direction: 1) == p)
}

@Test func hideKeepsPositionAndShowRestoresIt() {
    var p = TodayTilePrefs.default
    p = setTodayTileHidden(p, id: "rhr", hide: true)
    #expect(p.hidden == ["rhr"])
    #expect(p.order == ids)                                // hiding never moves a tile
    #expect(visibleTodayTileOrder(p) == ["hrv", "sleep", "steps"])
    p = setTodayTileHidden(p, id: "steps", hide: true)
    #expect(p.hidden == ["rhr", "steps"])                  // hidden is kept in `order` order
    p = setTodayTileHidden(p, id: "rhr", hide: false)
    #expect(p.hidden == ["steps"])
    #expect(visibleTodayTileOrder(p) == ["hrv", "rhr", "sleep"])
    #expect(setTodayTileHidden(p, id: "rhr", hide: false) == p)
}

@Test func reorderVisibleKeepsHiddenTilesInTheirSlots() {
    var p = TodayTilePrefs.default
    p = setTodayTileHidden(p, id: "rhr", hide: true)
    let r = reorderTodayTiles(p, newVisibleOrder: ["steps", "sleep", "hrv"])
    #expect(r.order == ["steps", "rhr", "sleep", "hrv"])
    #expect(r.hidden == ["rhr"])
}

@Test func reconcileDropsUnknownIdsAppendsNewOnesAndPrunesHidden() {
    let p = TodayTilePrefs.reconcile(order: ["ghost", "steps", "hrv"], hidden: ["ghost", "steps"])
    #expect(p.order == ["steps", "hrv", "rhr", "sleep"])
    #expect(p.hidden == ["steps"])
    #expect(TodayTilePrefs.reconcile(order: nil, hidden: nil) == .default)
}

// MARK: round-trip through PrefStore in TodayGrid's `today.tileOrder` format

@Test @MainActor func moveWritesTheOrderTodayGridReads() throws {
    let db = try AppDatabase.inMemory()
    let vm = EditTodayViewModel(prefs: PrefStore(db: db))
    vm.load()
    #expect(vm.prefs.order == ids)
    vm.move("steps", direction: -1)
    vm.move("steps", direction: -1)
    #expect(vm.prefs.order == ["hrv", "steps", "rhr", "sleep"])

    // TodayGrid's own reader (a fresh PrefStore over the same db) sees exactly what EditToday wrote.
    let grid = loadTileOrder(prefs: PrefStore(db: db), chipIDs: ids)
    #expect(grid == ["hrv", "steps", "rhr", "sleep"])
    #expect(try PrefStore(db: db).get(todayTileOrderKey, as: [String].self) == ["hrv", "steps", "rhr", "sleep"])
}

@Test @MainActor func hideShowRoundTripsAndNeverTouchesTheOrder() throws {
    let db = try AppDatabase.inMemory()
    let vm = EditTodayViewModel(prefs: PrefStore(db: db))
    vm.load()
    vm.setHidden("sleep", hide: true)
    #expect(vm.isHidden("sleep"))

    let relaunch = EditTodayViewModel(prefs: PrefStore(db: db))
    relaunch.load()
    #expect(relaunch.prefs.hidden == ["sleep"])
    #expect(relaunch.visibleOrder == ["hrv", "rhr", "steps"])
    #expect(try PrefStore(db: db).get(todayTileHiddenKey, as: [String].self) == ["sleep"])
    // `today.tileOrder` keeps the FULL order (RN `prefs.order` semantics), so TodayGrid's
    // resolver still yields a stable order with nothing dropped.
    #expect(loadTileOrder(prefs: PrefStore(db: db), chipIDs: ids) == ids)

    relaunch.setHidden("sleep", hide: false)
    #expect(relaunch.prefs == .default)
    #expect(try PrefStore(db: db).get(todayTileHiddenKey, as: [String].self) == [])
}

@Test @MainActor func editTodayLoadsAnOrderTodayGridPersisted() throws {
    let db = try AppDatabase.inMemory()
    saveTileOrder(["steps", "hrv", "rhr", "sleep"], prefs: PrefStore(db: db))   // a Today drag
    let vm = EditTodayViewModel(prefs: PrefStore(db: db))
    vm.load()
    #expect(vm.prefs.order == ["steps", "hrv", "rhr", "sleep"])
    #expect(vm.canMove("steps", direction: -1) == false)
    #expect(vm.canMove("sleep", direction: 1) == false)
    #expect(vm.canMove("hrv", direction: -1))
}

@Test @MainActor func nilPrefsStillEditsInMemoryWithoutCrashing() {
    let vm = EditTodayViewModel(prefs: nil)
    vm.load()
    vm.move("rhr", direction: -1)
    vm.setHidden("hrv", hide: true)
    #expect(vm.prefs.order == ["rhr", "hrv", "sleep", "steps"])
    #expect(vm.prefs.hidden == ["hrv"])
}

@Test @MainActor func editTodaySectionIsRegisteredInThePreferencesBand() {
    let ids = SettingsRegistry.sections.map(\.id)
    #expect(ids.contains(EditTodaySection.sectionId))
    let s = SettingsRegistry.sections.first { $0.id == EditTodaySection.sectionId }!
    #expect(SettingsGroup(sortKey: s.sortKey) == .preferences)
}

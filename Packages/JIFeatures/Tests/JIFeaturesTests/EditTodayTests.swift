import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// W5a-L3 (P-edit-today). Ports `mobile/__tests__/data/todayTilePrefs.test.ts` +
// `components/todayTileRegistry.test.ts` onto the Swift tile set (hrv/rhr/sleep/steps).

/// Today's four grid chips, then the squares the B-57 EditToday board adds (Load, Protein, Calories, Weight).
private let gridIds = ["hrv", "rhr", "sleep", "steps"]
private let extraIds = ["acwr", "protein", "kcal", "weight"]
private let ids = gridIds + extraIds

// MARK: registry (todayTileRegistry.test.ts)

@Test func registryListsEveryTodayChipId() {
    // TodayViewModel.chips is the fixed hrv/rhr/sleep/steps set (TodayViewModel.swift L112–115).
    #expect(TodayTileRegistry.ids == ids)
    for id in TodayTileRegistry.ids { #expect(TodayTileRegistry.label(for: id).isEmpty == false) }
}

@Test @MainActor func registryMatchesLiveViewModelChips() async throws {
    let vm = TodayViewModel(provider: FlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.squareChips.map(\.id) == TodayTileRegistry.ids)
    #expect(vm.squareChips.map(\.label) == TodayTileRegistry.ids.map { TodayTileRegistry.label(for: $0) })
    // Today's grid (and the widget snapshot) keep exactly the four chips.
    #expect(vm.chips.map(\.id) == gridIds)
}

// MARK: pure prefs ops (todayTilePrefs.test.ts)

@Test func defaultPrefsAreRegistryOrderWithNothingHidden() {
    let p = TodayTilePrefs.default
    #expect(p.order == ids)
    #expect(p.hidden.isEmpty)
}

@Test func moveSwapsOneSlotAndIsANoOpAtTheEnds() {
    let p = TodayTilePrefs.default
    #expect(moveTodayTile(p, id: "rhr", direction: -1).order == ["rhr", "hrv", "sleep", "steps"] + extraIds)
    #expect(moveTodayTile(p, id: "rhr", direction: 1).order == ["hrv", "sleep", "rhr", "steps"] + extraIds)
    #expect(moveTodayTile(p, id: "hrv", direction: -1) == p)
    #expect(moveTodayTile(p, id: "weight", direction: 1) == p)
    #expect(moveTodayTile(p, id: "ghost", direction: 1) == p)
}

@Test func hideKeepsPositionAndShowRestoresIt() {
    var p = TodayTilePrefs.default
    p = setTodayTileHidden(p, id: "rhr", hide: true)
    #expect(p.hidden == ["rhr"])
    #expect(p.order == ids)                                // hiding never moves a tile
    #expect(visibleTodayTileOrder(p) == ["hrv", "sleep", "steps"] + extraIds)
    p = setTodayTileHidden(p, id: "steps", hide: true)
    #expect(p.hidden == ["rhr", "steps"])                  // hidden is kept in `order` order
    p = setTodayTileHidden(p, id: "rhr", hide: false)
    #expect(p.hidden == ["steps"])
    #expect(visibleTodayTileOrder(p) == ["hrv", "rhr", "sleep"] + extraIds)
    #expect(setTodayTileHidden(p, id: "rhr", hide: false) == p)
}

@Test func reorderVisibleKeepsHiddenTilesInTheirSlots() {
    var p = TodayTilePrefs.default
    p = setTodayTileHidden(p, id: "rhr", hide: true)
    let r = reorderTodayTiles(p, newVisibleOrder: ["steps", "sleep", "hrv"] + extraIds)
    #expect(r.order == ["steps", "rhr", "sleep", "hrv"] + extraIds)
    #expect(r.hidden == ["rhr"])
}

@Test func reconcileDropsUnknownIdsAppendsNewOnesAndPrunesHidden() {
    let p = TodayTilePrefs.reconcile(order: ["ghost", "steps", "hrv"], hidden: ["ghost", "steps"])
    #expect(p.order == ["steps", "hrv", "rhr", "sleep"] + extraIds)
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
    #expect(vm.prefs.order == ["hrv", "steps", "rhr", "sleep"] + extraIds)

    // TodayGrid's own reader (a fresh PrefStore over the same db) sees exactly what EditToday wrote.
    let grid = loadTileOrder(prefs: PrefStore(db: db), chipIDs: gridIds)
    #expect(grid == ["hrv", "steps", "rhr", "sleep"])
    #expect(try PrefStore(db: db).get(todayTileOrderKey, as: [String].self) == ["hrv", "steps", "rhr", "sleep"] + extraIds)
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
    #expect(relaunch.visibleOrder == ["hrv", "rhr", "steps"] + extraIds)
    #expect(try PrefStore(db: db).get(todayTileHiddenKey, as: [String].self) == ["sleep"])
    // `today.tileOrder` keeps the FULL order (RN `prefs.order` semantics), so TodayGrid's
    // resolver still yields a stable order with nothing dropped.
    #expect(loadTileOrder(prefs: PrefStore(db: db), chipIDs: gridIds) == gridIds)

    relaunch.setHidden("sleep", hide: false)
    #expect(relaunch.prefs == .default)
    #expect(try PrefStore(db: db).get(todayTileHiddenKey, as: [String].self) == [])
}

@Test @MainActor func editTodayLoadsAnOrderTodayGridPersisted() throws {
    let db = try AppDatabase.inMemory()
    saveTileOrder(["steps", "hrv", "rhr", "sleep"], prefs: PrefStore(db: db))   // a Today drag
    let vm = EditTodayViewModel(prefs: PrefStore(db: db))
    vm.load()
    #expect(vm.prefs.order == ["steps", "hrv", "rhr", "sleep"] + extraIds)
    #expect(vm.canMove("steps", direction: -1) == false)
    #expect(vm.canMove("weight", direction: 1) == false)
    #expect(vm.canMove("hrv", direction: -1))
}

@Test @MainActor func nilPrefsStillEditsInMemoryWithoutCrashing() {
    let vm = EditTodayViewModel(prefs: nil)
    vm.load()
    vm.move("rhr", direction: -1)
    vm.setHidden("hrv", hide: true)
    #expect(vm.prefs.order == ["rhr", "hrv", "sleep", "steps"] + extraIds)
    #expect(vm.prefs.hidden == ["hrv"])
}

@Test @MainActor func editTodaySectionIsRegisteredInThePreferencesBand() {
    let ids = SettingsRegistry.sections.map(\.id)
    #expect(ids.contains(EditTodaySection.sectionId))
    let s = SettingsRegistry.sections.first { $0.id == EditTodaySection.sectionId }!
    #expect(SettingsGroup(sortKey: s.sortKey) == .preferences)
}

@Test func squaresSplitVisibleAndHiddenWithBadges() {
    let p = TodayTilePrefs(order: ["hrv", "rhr", "sleep", "steps"], hidden: ["rhr"])
    #expect(editTodayVisibleItems(p).map(\.id) == ["hrv", "sleep", "steps"])
    #expect(editTodayVisibleItems(p).allSatisfy { $0.badge == .hide })
    #expect(editTodayHiddenItems(p).map(\.id) == ["rhr"])
    #expect(editTodayHiddenItems(p).allSatisfy { $0.badge == .add })
    #expect(editTodayCountText(p) == "3 of 4")
}

@Test @MainActor func dragMovesWithinTheVisibleOrderAndPersists() throws {
    let db = try AppDatabase.inMemory()
    let vm = EditTodayViewModel(prefs: PrefStore(db: db))
    vm.load()
    vm.moveSquare("steps", before: "hrv")
    #expect(vm.visibleOrder == ["steps", "hrv", "rhr", "sleep"] + extraIds)
    vm.setPageName("  Morning ")
    #expect(vm.pageName == "Morning")
    #expect(loadTodayPageName(prefs: PrefStore(db: db)) == "Morning")
}

/// B-57 W1 board: EditToday squares show Today's values; a missing one carries a reason word.
@Test func editTodaySquaresShowTodaysValuesAndReasonWords() {
    let p = TodayTilePrefs(order: ["hrv", "rhr", "sleep", "steps"], hidden: ["rhr"])
    let chips = [
        TodayChip(id: "hrv", label: "HRV", value: 48, unit: "ms", points: [], sourceMissing: false),
        TodayChip(id: "sleep", label: "Sleep", value: nil, unit: nil, points: [], sourceMissing: true),
        TodayChip(id: "steps", label: "Steps", value: nil, unit: nil, points: [], sourceMissing: false),
        TodayChip(id: "rhr", label: "RHR", value: 52, unit: "bpm", points: [], sourceMissing: false),
    ]
    let visible = editTodayVisibleItems(p, chips: chips)
    #expect(visible.map(\.value) == [48, nil, nil])
    #expect(visible[0].unit == "ms" && visible[0].status == nil)
    #expect(visible[1].status == .missing(.notInHealthYet))
    #expect(visible[2].status == .missing(.noData))
    #expect(editTodayHiddenItems(p, chips: chips).first?.value == 52)
    // No chips reached the screen: every square still says why it is empty.
    #expect(editTodayVisibleItems(p).allSatisfy { $0.value == nil && $0.status == .missing(.noData) })
}

/// Verifier W-B57-W1 (board EditToday): Load, Protein, Calories and Weight are squares too, each
/// with its own icon, and a value from Today's data or "—" + a reason word.
@Test func boardSquaresCarryTheirOwnLabelsIconsAndDecimals() {
    #expect(extraIds.map { TodayTileRegistry.label(for: $0) } == ["Load", "Protein", "Calories", "Weight"])
    #expect(Set(ids.map { TodayTileRegistry.systemImage(for: $0) }).count == ids.count)
    #expect(TodayTileRegistry.decimals(for: "weight") == 1 && TodayTileRegistry.decimals(for: "acwr") == 2)
    let p = TodayTilePrefs.default
    let chips = [TodayChip(id: "weight", label: "Weight", value: 80.2, unit: "kg", points: [], sourceMissing: false)]
    let items = editTodayVisibleItems(p, chips: chips)
    let weight = items.first { $0.id == "weight" }
    #expect(weight?.value == 80.2 && weight?.decimals == 1 && weight?.unit == "kg" && weight?.status == nil)
    #expect(items.first { $0.id == "protein" }?.status == .missing(.noData))
}

@Test @MainActor func squareChipsReadTodaysRealData() async throws {
    let vm = TodayViewModel(provider: FlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    let byId = Dictionary(uniqueKeysWithValues: vm.squareChips.map { ($0.id, $0) })
    let daily = vm.gate?.daily ?? []
    let food = resolveTodayRow(daily).row
    #expect(byId["protein"]?.value == (food?.values["protein_g"] ?? nil))
    #expect(byId["kcal"]?.value == (food?.values["kcal_consumed"] ?? nil))
    // W-FIX1 BUG-12: Load is the current ACWR (≤ 36 h) or "—" — never a stale newest value.
    #expect(byId["acwr"]?.value == vm.heroLoad)
    #expect(byId["weight"]?.value == daily.sorted { $0.date > $1.date }.compactMap { $0.values["weight_kg"] ?? nil }.first)
}

/// Board: the dashed "+ Add" square closes the grid; W-FIX2 BUG-20: it opens the catalogue, which
/// lists every square (✓ on Today, + hidden), so it is never inert.
@Test func addSquareCatalogueMarksOnTodayAndHidden() {
    #expect(editTodayCatalogueItems(.default).allSatisfy { $0.badge == .selected })
    let p = setTodayTileHidden(.default, id: "kcal", hide: true)
    #expect(editTodayCatalogueItems(p).filter { $0.badge == .add }.map(\.id) == ["kcal"])
}

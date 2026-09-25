import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// W-FIX2 L4: BUG-19 (EditToday = what Today shows), BUG-20 (Add opens the catalogue),
// BUG-25 (pending glyph clears after any drain), BUG-48 (weekday picker without a stray label).

// MARK: - BUG-19

@Test func todayGridShowsExactlyEditTodaysOnTodaySet() {
    let all = TodayTileRegistry.ids
    // Nothing hidden: every square EditToday lists is on Today, in the same order.
    #expect(todayGridShownIDs(chipIDs: all, prefs: .default) == visibleTodayTileOrder(.default))
    // Hiding a square in EditToday removes it from Today; order follows EditToday's.
    var p = setTodayTileHidden(.default, id: "acwr", hide: true)
    p = setTodayTileHidden(p, id: "hrv", hide: true)
    p = moveTodayTile(p, id: "weight", direction: -1)
    #expect(todayGridShownIDs(chipIDs: all, prefs: p) == ["rhr", "sleep", "steps", "protein", "weight", "kcal"])
    #expect(todayGridShownIDs(chipIDs: all, prefs: p) == editTodayVisibleItems(p).map(\.id))
    // Showing it again brings it back in its old slot.
    #expect(todayGridShownIDs(chipIDs: all, prefs: setTodayTileHidden(p, id: "hrv", hide: false)).first == "hrv")
}

@Test func todayGridNeverInventsASquareItHasNoChipFor() {
    #expect(todayGridShownIDs(chipIDs: ["hrv", "rhr"], prefs: .default) == ["hrv", "rhr"])
    // An unregistered chip id still renders (appended), never dropped.
    #expect(todayGridShownIDs(chipIDs: ["hrv", "mystery"], prefs: .default) == ["hrv", "mystery"])
}

@Test func aTodayDragKeepsHiddenSquaresHiddenAndInPlace() {
    let p = setTodayTileHidden(.default, id: "rhr", hide: true)
    let shown = todayGridShownIDs(chipIDs: TodayTileRegistry.ids, prefs: p)
    let dragged = squareGridMove(shown, moving: "weight", before: "hrv")
    let next = todayGridCommitOrder(p, shownOrder: dragged)
    #expect(next.hidden == ["rhr"])
    #expect(next.order.count == TodayTileRegistry.ids.count)
    #expect(visibleTodayTileOrder(next) == dragged)
    #expect(next.order[1] == "rhr")   // the hidden square keeps its slot
}

@Test @MainActor func todayGridReadsTheHiddenSetEditTodayWrote() throws {
    let db = try AppDatabase.inMemory()
    let edit = EditTodayViewModel(prefs: PrefStore(db: db))
    edit.load()
    edit.setHidden("kcal", hide: true)
    let shown = todayGridShownIDs(chipIDs: TodayTileRegistry.ids, prefs: loadTodayTilePrefs(prefs: PrefStore(db: db)))
    #expect(!shown.contains("kcal"))
    #expect(shown == edit.visibleOrder)
}

// MARK: - BUG-20

@Test @MainActor func addOpensTheCatalogueAndItsBadgesChangeToday() throws {
    let db = try AppDatabase.inMemory()
    let vm = EditTodayViewModel(prefs: PrefStore(db: db))
    vm.load()
    #expect(vm.showsAddCatalogue == false)
    vm.openAddCatalogue()
    #expect(vm.showsAddCatalogue)   // even with nothing hidden: the catalogue lists what is on Today

    let items = editTodayCatalogueItems(vm.prefs)
    #expect(items.map(\.id) == TodayTileRegistry.ids)
    #expect(items.allSatisfy { $0.badge == .selected })

    vm.toggleFromCatalogue("protein")            // ✓ → removes it from Today
    #expect(vm.isHidden("protein"))
    #expect(editTodayCatalogueItems(vm.prefs).first { $0.id == "protein" }?.badge == .add)
    vm.toggleFromCatalogue("protein")            // + → adds it back
    #expect(!vm.isHidden("protein"))
    #expect(try PrefStore(db: db).get(todayTileHiddenKey, as: [String].self) == [])
}

// MARK: - BUG-25

@MainActor
private func makeTrainingVM(hub: PlanWeekdayFakeProvider, outbox: Outbox) throws -> TrainingViewModel {
    TrainingViewModel(
        provider: hub, healthProvider: MockDataProvider(), cache: OfflineCache(db: try AppDatabase.inMemory()),
        strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "fix2l4.\(UUID().uuidString)")),
        outbox: outbox,
        drainer: OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub),
        now: { ISO8601DateFormatter().date(from: "2026-09-25T08:00:00Z")! }
    )
}

@Test @MainActor func thePendingGlyphClearsWhenAnotherOwnerDrainsWhileTheScreenIsUp() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.network("offline")
    let vm = try makeTrainingVM(hub: hub, outbox: outbox)
    await vm.load()
    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)
    #expect(vm.pendingSessionSync.contains(7))

    // The watcher is running (the screen is up) when the retry scheduler / watchdog drains.
    let watcher = Task { await vm.watchPendingSync(every: .milliseconds(20)) }
    hub.weekdayError = nil
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub).drainOnForeground()
    await watcher.value   // returns on its own once nothing is pending

    #expect(vm.pendingSessionSync.isEmpty)
    #expect(vm.exercises.first?.weekday == 3)
}

@Test @MainActor func thePendingGlyphClearsWhenTheScreenReappearsAfterADrain() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.network("offline")
    let vm = try makeTrainingVM(hub: hub, outbox: outbox)
    await vm.load()
    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)
    hub.weekdayError = nil
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub).drainOnForeground()
    #expect(vm.hasLiveResult)          // so `.task` will NOT reload on the tab switch back
    vm.screenAppeared()                // …but the appearance reconciles
    #expect(vm.pendingSessionSync.isEmpty)
}

@Test @MainActor func theWatcherStopsAtOnceWhenNothingIsPending() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let vm = try makeTrainingVM(hub: PlanWeekdayFakeProvider(), outbox: outbox)
    await vm.watchPendingSync(every: .seconds(60))   // would hang the test if it slept first
    #expect(vm.pendingSessionSync.isEmpty)
}

// MARK: - BUG-48

@Test @MainActor func theWeekdayPickerListsNotAssignedThenMonToSunAndHidesItsLabel() {
    #expect(AssignWeekdaySheet.pickerOptions.map(\.title) == ["Not assigned"] + planWeekdayNames)
    #expect(AssignWeekdaySheet.pickerOptions.map(\.tag) == [-1, 0, 1, 2, 3, 4, 5, 6])
    #expect(AssignWeekdaySheet.showsPickerLabel == false)
}

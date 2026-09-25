import Foundation
import Testing
import JICore
import JIDesign
import JIPersistence
@testable import JIFeatures

// W-FIX3 L3 C-a (BUG-19 rest): My KPIs "On Today" = EditToday's set — ONE store
// (`KpiSelection.prefKey`), and Today re-reads it the moment a sheet that edits it closes.

private func stored(_ store: PrefStore) throws -> KpiSelectionPrefs? { try store.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self) }
private func visible(_ p: KpiSelectionPrefs?) -> [String] { KpiSelection.visibleOrder(KpiSelection.reconcile(p)).map(\.rawValue) }

@Test func everyKpiIsAPossibleTodaySquare() {
    #expect(Set(TodayTileRegistry.ids) == Set(KpiMetricId.allCases.map(\.rawValue)))
    for id in TodayTileRegistry.ids { #expect(!TodayTileRegistry.label(for: id).isEmpty) }
}

@Test @MainActor func todaysSquaresCoverEveryKpi() async throws {
    let vm = TodayViewModel(provider: FlakyProvider(failing: false), cache: OfflineCache(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.squareChips.map(\.id) == TodayTileRegistry.ids)
}

@Test @MainActor func editTodayWritesTheSelectionMyKpisReads() throws {
    let store = PrefStore(db: try AppDatabase.inMemory())
    let vm = EditTodayViewModel(prefs: store)
    vm.load()
    vm.setHidden("steps", hide: true)
    let myKpis = visible(try stored(store))
    #expect(myKpis == vm.visibleOrder)
    #expect(!myKpis.contains("steps"))
}

@Test @MainActor func aMyKpisTickShowsInEditTodayAndOnToday() throws {
    let store = PrefStore(db: try AppDatabase.inMemory())
    EditTodayViewModel(prefs: store).load()   // seeds the one store
    // What KpiListViewModel.toggle does: setSelected + write the same key.
    let next = KpiSelection.setSelected(KpiSelection.reconcile(try stored(store)), id: .protein, selected: false)
    try store.set(KpiSelection.prefKey, next)
    let today = loadTodayTilePrefs(prefs: store)
    #expect(visibleTodayTileOrder(today) == visible(next))
    #expect(todayGridShownIDs(chipIDs: TodayTileRegistry.ids, prefs: today) == visible(next))
}

@Test func aPreFix3EditTodaySetWinsOnceAndBecomesTheSelection() throws {
    let store = PrefStore(db: try AppDatabase.inMemory())
    try store.set(todayTileOrderKey, ["steps", "hrv", "rhr", "sleep", "acwr", "protein", "kcal", "weight"])
    try store.set(todayTileHiddenKey, ["kcal"])
    // an old My KPIs selection that disagreed with EditToday
    try store.set(KpiSelection.prefKey, KpiSelection.defaultPrefs())
    try store.remove(todayTilesUnifiedKey)
    let p = loadTodayTilePrefs(prefs: store)
    #expect(visibleTodayTileOrder(p) == ["steps", "hrv", "rhr", "sleep", "acwr", "protein", "weight"])
    #expect(visible(try stored(store)) == visibleTodayTileOrder(p))
}

@Test func aFreshInstallSeedsTheOneStoreWithTheBoardDefault() throws {
    let store = PrefStore(db: try AppDatabase.inMemory())
    let p = loadTodayTilePrefs(prefs: store)
    #expect(p == .default)
    #expect(visible(try stored(store)) == visibleTodayTileOrder(.default))
}

@Test func savingAnnouncesTheChangeSoTodayReReads() throws {
    let store = PrefStore(db: try AppDatabase.inMemory())
    // @unchecked: test-only counter; the post is delivered synchronously on this thread (queue: nil).
    final class Heard: @unchecked Sendable { var count = 0 }
    let heard = Heard()
    let token = NotificationCenter.default.addObserver(forName: todayTilePrefsDidChange, object: nil, queue: nil) { _ in heard.count += 1 }
    defer { NotificationCenter.default.removeObserver(token) }
    saveTodayTilePrefs(setTodayTileHidden(.default, id: "rhr", hide: true), prefs: store)
    #expect(heard.count >= 1)   // other tests may save in parallel
}

@Test @MainActor func editTodayKeepsMyKpisLimits() throws {
    let store = PrefStore(db: try AppDatabase.inMemory())
    let vm = EditTodayViewModel(prefs: store)
    vm.load()
    #expect(vm.visibleOrder.count == KpiSelection.maxSelected)
    vm.setHidden("readiness", hide: false)          // a 9th square: refused
    #expect(vm.isHidden("readiness"))
    for id in ["hrv", "rhr", "sleep", "steps", "acwr", "protein"] { vm.setHidden(id, hide: true) }
    #expect(vm.visibleOrder.count == KpiSelection.minSelected)
}

import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

@Test func defaultPrefsMatchOracleComposition() {
    let prefs = KpiSelection.defaultPrefs()
    let visible = Set(KpiSelection.visibleOrder(prefs))
    #expect(visible == Set([.hrv, .rhr, .sleep, .steps, .bodyBattery, .readiness, .acwr]))
}

@Test func setSelectedRefusesBelowFloor() {
    var prefs = KpiSelection.defaultPrefs() // 7 selected
    for id in [KpiMetricId.hrv, .rhr, .sleep, .steps] { prefs = KpiSelection.setSelected(prefs, id: id, selected: false) }
    // Now at the floor (3 selected: bodyBattery, readiness, acwr) — one more refusal.
    let result = KpiSelection.setSelected(prefs, id: .bodyBattery, selected: false)
    #expect(result == prefs)
}

@Test func setSelectedRefusesAboveCeiling() {
    var prefs = KpiSelection.defaultPrefs() // 7 selected
    let result = KpiSelection.setSelected(prefs, id: .kcal, selected: true) // -> 8, at ceiling, allowed
    #expect(KpiSelection.visibleOrder(result).count == 8)
    let refused = KpiSelection.setSelected(result, id: .protein, selected: true) // -> would be 9, refused
    #expect(refused == result)
    prefs = result
}

@Test func moveIsNoOpAtEitherEndOfVisibleList() {
    let prefs = KpiSelection.defaultPrefs()
    let visible = KpiSelection.visibleOrder(prefs)
    let first = visible[0]
    #expect(KpiSelection.move(prefs, id: first, direction: -1) == prefs)
    let last = visible[visible.count - 1]
    #expect(KpiSelection.move(prefs, id: last, direction: 1) == prefs)
}

@Test func moveSwapsRankWithinVisibleSubsetOnly() {
    let prefs = KpiSelection.defaultPrefs()
    let visible = KpiSelection.visibleOrder(prefs)
    let moved = KpiSelection.move(prefs, id: visible[1], direction: -1)
    let newVisible = KpiSelection.visibleOrder(moved)
    #expect(newVisible[0] == visible[1])
    #expect(newVisible[1] == visible[0])
}

@Test func reconcileFallsBackToDefaultsOnEmptyOrder() {
    let reconciled = KpiSelection.reconcile(KpiSelectionPrefs(order: [], hidden: []))
    #expect(reconciled == KpiSelection.defaultPrefs())
}

/// Card exit criterion: "selection persists (PrefStore test)".
@Test func selectionPersistsThroughPrefStore() throws {
    let store = PrefStore(db: try AppDatabase.inMemory())
    var prefs = KpiSelection.defaultPrefs()
    prefs = KpiSelection.setSelected(prefs, id: .kcal, selected: true)
    try store.set(KpiSelection.prefKey, prefs)

    let reloaded = try store.get(KpiSelection.prefKey, as: KpiSelectionPrefs.self)
    #expect(reloaded == prefs)
    #expect(KpiSelection.visibleOrder(reloaded!).contains(.kcal))
}

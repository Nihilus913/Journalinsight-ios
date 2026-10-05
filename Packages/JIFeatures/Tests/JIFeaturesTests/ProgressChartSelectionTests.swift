import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

@Suite struct ProgressChartSelectionTests {
    let bench = ProgressChartID.lift(key: "Barbell Bench Press", metric: .e1rm)
    let row = ProgressChartID.lift(key: "Barbell Row", metric: .volume)
    let pace = ProgressChartID.run(.pace)
    let vo2 = ProgressChartID.vo2max

    @Test func defaultIsEmpty() {
        let prefs = ProgressChartSelection.defaultPrefs()
        #expect(prefs.pinned.isEmpty)
        #expect(prefs.hidden.isEmpty)
        #expect(ProgressChartSelection.reconcile(nil) == prefs)
        #expect(ProgressChartSelection.prefKey == "progress_charts.prefs.v1")
    }

    @Test func pinAppendsAndIsIdempotent() {
        var p = ProgressChartSelection.defaultPrefs()
        p = ProgressChartSelection.pin(p, bench)
        p = ProgressChartSelection.pin(p, pace)
        #expect(p.pinned == [bench, pace])
        #expect(ProgressChartSelection.pin(p, bench) == p)
        #expect(ProgressChartSelection.isPinned(p, pace))
    }

    @Test func pinUnhides() {
        let p = ProgressChartSelection.pin(ProgressChartPrefs(hidden: [vo2]), vo2)
        #expect(p.pinned == [vo2])
        #expect(p.hidden.isEmpty)
    }

    @Test func unpinRemovesAndIsNoOpWhenAbsent() {
        let p = ProgressChartPrefs(pinned: [bench, pace, vo2])
        let u = ProgressChartSelection.unpin(p, pace)
        #expect(u.pinned == [bench, vo2])
        #expect(ProgressChartSelection.unpin(u, pace) == u)
    }

    @Test func hideUnpinsAndShowRestores() {
        let p = ProgressChartPrefs(pinned: [bench, pace])
        let h = ProgressChartSelection.setHidden(p, bench, hidden: true)
        #expect(h.pinned == [pace])
        #expect(h.hidden == [bench])
        let s = ProgressChartSelection.setHidden(h, bench, hidden: false)
        #expect(s.hidden.isEmpty)
        #expect(ProgressChartSelection.setHidden(s, bench, hidden: false) == s)
    }

    @Test func reorderSwapsAndIsNoOpAtEnds() {
        let p = ProgressChartPrefs(pinned: [bench, pace, vo2])
        #expect(ProgressChartSelection.move(p, pace, direction: -1).pinned == [pace, bench, vo2])
        #expect(ProgressChartSelection.move(p, pace, direction: 1).pinned == [bench, vo2, pace])
        #expect(ProgressChartSelection.move(p, bench, direction: -1) == p)
        #expect(ProgressChartSelection.move(p, vo2, direction: 1) == p)
        #expect(ProgressChartSelection.move(p, row, direction: 1) == p)
    }

    @Test func reorderWithOnMoveOffsets() {
        let p = ProgressChartPrefs(pinned: [bench, pace, vo2, row])
        // Drag first to the end (SwiftUI passes destination = count).
        #expect(ProgressChartSelection.move(p, fromOffsets: IndexSet(integer: 0), toOffset: 4).pinned == [pace, vo2, row, bench])
        // Drag last to the top.
        #expect(ProgressChartSelection.move(p, fromOffsets: IndexSet(integer: 3), toOffset: 0).pinned == [row, bench, pace, vo2])
        // Out of range -> same value.
        #expect(ProgressChartSelection.move(p, fromOffsets: IndexSet(integer: 9), toOffset: 0) == p)
    }

    @Test func reconcileDropsStaleAndDuplicateIds() {
        let raw = ProgressChartPrefs(pinned: [bench, pace, bench, row], hidden: [pace, vo2])
        let r = ProgressChartSelection.reconcile(raw, available: [bench, pace, vo2])
        #expect(r.pinned == [bench, pace])   // row stale, duplicate bench dropped, order kept
        #expect(r.hidden == [vo2])           // pace pinned wins over hidden
        // Without an availability set only duplicates/conflicts are cleaned.
        #expect(ProgressChartSelection.reconcile(raw).pinned == [bench, pace, row])
    }

    @Test func decodeDropsUnknownIdStrings() throws {
        let json = #"{"pinned":["lift:Barbell Row:volume","lift:Plank:cadence","run:power","vo2max","bogus","lift::e1rm"],"hidden":["run:pace"]}"#
        let p = try JSONDecoder().decode(ProgressChartPrefs.self, from: Data(json.utf8))
        #expect(p.pinned == [row, vo2])
        #expect(p.hidden == [pace])
        let empty = try JSONDecoder().decode(ProgressChartPrefs.self, from: Data("{}".utf8))
        #expect(empty == ProgressChartSelection.defaultPrefs())
    }

    @Test func codableRoundTrip() throws {
        let ids: [ProgressChartID] = LiftChartMetric.allCases.map { .lift(key: "Odd: Name", metric: $0) }
            + RunChartMetric.allCases.map { .run($0) } + [.vo2max]
        for id in ids { #expect(ProgressChartID(rawValue: id.rawValue) == id) }
        let prefs = ProgressChartPrefs(pinned: ids, hidden: [])
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(ProgressChartPrefs.self, from: data) == prefs)
    }

    @Test func persistsThroughPrefStore() throws {
        let store = PrefStore(db: try AppDatabase.inMemory())
        #expect(try store.get(ProgressChartSelection.prefKey, as: ProgressChartPrefs.self) == nil)
        let prefs = ProgressChartPrefs(pinned: [pace, bench], hidden: [vo2])
        try store.set(ProgressChartSelection.prefKey, prefs)
        #expect(try store.get(ProgressChartSelection.prefKey, as: ProgressChartPrefs.self) == prefs)
    }

    @Test func displayOrderPinsFirstHiddenOut() {
        let prefs = ProgressChartPrefs(pinned: [vo2, row], hidden: [pace])
        let order = ProgressChartSelection.displayOrder(prefs, available: [bench, pace, vo2])
        #expect(order == [vo2, bench])   // row pinned but unavailable; pace hidden
    }
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-B96 C-2 (B-96): the Settings toggle's model. Off by default; on → write-only access → only
// keys not yet in the ledger are written (write-only access cannot read events back, so the
// ledger is what prevents duplicates); denied → snaps off, nothing written.
@MainActor private final class FakeWriter: CalendarEventWriting {
    var grant = true
    var failKeys: Set<String> = []
    var written: [PlannedCalendarEvent] = []
    var asked = 0
    func requestAccess() async -> Bool { asked += 1; return grant }
    func write(_ event: PlannedCalendarEvent) async throws {
        if failKeys.contains(event.key) { throw CocoaError(.fileWriteUnknown) }
        written.append(event)
    }
}

private func week(_ start: String, ids: [Int?]) -> PlanWeekOut {
    let mon = DayKey(iso: start)!
    return PlanWeekOut(start: start, days: ids.enumerated().map { i, id in
        PlanWeekDayOut(date: mon.adding(days: i).iso, weekday: i, sessionId: id, name: id == 7 ? "Rest" : "S\(id ?? 0)",
                       sessionType: id == 7 ? "rest" : "strength", prescription: "p", type: id == 7 ? "rest" : "strength")
    })
}

private let tobyIds: [Int?] = [1, 5, 2, 6, 3, 8, 7]
private let now = DayKey(iso: "2026-10-05")!.startDate(in: TimeZone(identifier: "Europe/Zurich")!).addingTimeInterval(7 * 3600)

@MainActor private func makeModel(_ writer: FakeWriter, prefs: PrefStore, weeks: [PlanWeekOut]) -> CalendarExportModel {
    CalendarExportModel(writer: writer, prefs: prefs, weeks: { weeks }, now: { now },
                        zone: { TimeZone(identifier: "Europe/Zurich")! })
}

@Test @MainActor func calendarExportIsOffByDefaultAndWritesNothing() async throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let w = FakeWriter()
    let m = makeModel(w, prefs: prefs, weeks: [week("2026-10-05", ids: tobyIds)])
    await m.sync()
    #expect(m.enabled == false)
    #expect(m.state == .off)
    #expect(w.asked == 0 && w.written.isEmpty)
}

@Test @MainActor func calendarExportGrantWritesOnceThenNeverDuplicates() async throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let w = FakeWriter()
    let m = makeModel(w, prefs: prefs, weeks: [week("2026-10-05", ids: tobyIds)])
    await m.setEnabled(true)
    #expect(w.written.count == 6)   // Mon–Sat; Sun rest never
    #expect(m.state == .synced(added: 6, at: now))
    await m.sync()
    #expect(w.written.count == 6)
    #expect(m.state == .synced(added: 0, at: now))
    // a fresh model on the same prefs (app relaunch) remembers both the toggle and the ledger.
    let m2 = makeModel(w, prefs: prefs, weeks: [week("2026-10-05", ids: tobyIds)])
    #expect(m2.enabled)
    await m2.sync()
    #expect(w.written.count == 6)
}

@Test @MainActor func calendarExportDeniedSnapsOffAndWritesNothing() async throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let w = FakeWriter(); w.grant = false
    let m = makeModel(w, prefs: prefs, weeks: [week("2026-10-05", ids: tobyIds)])
    await m.setEnabled(true)
    #expect(m.enabled == false)
    #expect(m.state == .denied)
    #expect(w.written.isEmpty)
}

@Test @MainActor func calendarExportWithoutAWeekSaysSo() async throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let w = FakeWriter()
    let m = makeModel(w, prefs: prefs, weeks: [])
    await m.setEnabled(true)
    #expect(m.state == .noWeek)
    #expect(w.written.isEmpty)
    #expect(m.enabled)   // stays on: writes once the week is cached
}

@Test @MainActor func calendarExportFailedEventIsRetriedNextTime() async throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let w = FakeWriter(); w.failKeys = ["ji.plan.5.2026-10-06"]
    let m = makeModel(w, prefs: prefs, weeks: [week("2026-10-05", ids: tobyIds)])
    await m.setEnabled(true)
    #expect(w.written.count == 5)
    #expect(m.state == .synced(added: 5, at: now))
    w.failKeys = []
    await m.sync()
    #expect(w.written.map(\.key) .last == "ji.plan.5.2026-10-06")
    #expect(w.written.count == 6)
}

@Test @MainActor func calendarExportPreviewListsSevenDaysWithRest() async throws {
    let prefs = PrefStore(db: try AppDatabase.inMemory())
    let m = makeModel(FakeWriter(), prefs: prefs, weeks: [week("2026-10-05", ids: tobyIds)])
    await m.load()
    #expect(m.preview.count == 7)
    #expect(m.preview.last?.isRest == true)
    #expect(m.preview.first?.title == "S1")
}

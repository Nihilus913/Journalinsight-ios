import Foundation
import SwiftUI
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-B96 C-4 (B-96): the Calendar section sits under Reminders in Haptics & notifications and
// renders its off / on / denied states (mockup BP-24 frames 01/02/05).
@MainActor private final class StubWriter: CalendarEventWriting {
    var grant: Bool
    init(grant: Bool) { self.grant = grant }
    func requestAccess() async -> Bool { grant }
    func write(_ event: PlannedCalendarEvent) async throws {}
}

@Test @MainActor func calendarSectionLivesInHapticsUnderReminders() {
    let ids = GroupSettingsView.sections(in: .haptics).map(\.id)
    #expect(ids.contains(CalendarSection.sectionId))
    let r = ids.firstIndex(of: RemindersSection.sectionId), c = ids.firstIndex(of: CalendarSection.sectionId)
    #expect(r != nil && c != nil && r! < c!)
}

@Test func calendarStatusCopy() {
    let zrh = TimeZone(identifier: "Europe/Zurich")!
    let at = DayKey(iso: "2026-10-05")!.startDate(in: zrh).addingTimeInterval(7 * 3600 + 41 * 60)
    #expect(calendarExportStatus(.off, written: 0, zone: zrh) == nil)
    #expect(calendarExportStatus(.denied, written: 0, zone: zrh) == "access off")
    #expect(calendarExportStatus(.writing(done: 7, total: 12), written: 7, zone: zrh) == "writing… 7 of 12")
    #expect(calendarExportStatus(.synced(added: 0, at: at), written: 12, zone: zrh) == "12 added · 07:41")
    #expect(calendarPreviewDate("2026-10-05") == "Mon 5")
    #expect(calendarExportCaption.contains("never reads your calendar"))
    #expect(calendarExportCaption.contains("all-day"))
}

@Test @MainActor func calendarSectionRendersEveryState() async throws {
    for grant in [true, false] {
        let prefs = PrefStore(db: try AppDatabase.inMemory())
        let week = PlanWeekOut(start: "2026-10-05", days: [
            PlanWeekDayOut(date: "2026-10-05", weekday: 0, sessionId: 1, name: "Day 1 Full Upper", sessionType: "strength", prescription: "p", type: "strength"),
            PlanWeekDayOut(date: "2026-10-11", weekday: 6, sessionId: 7, name: "Rest", sessionType: "rest", prescription: "Rest", type: "rest"),
        ])
        let model = CalendarExportModel(writer: StubWriter(grant: grant), prefs: prefs, weeks: { [week] },
                                        now: { DayKey(iso: "2026-10-05")!.startDate(in: .gmt) }, zone: { .gmt })
        await model.load()
        let off = Form { CalendarExportRows(model: model) }.frame(width: 402, height: 874)
        #expect(ImageRenderer(content: off).cgImage != nil)
        await model.setEnabled(true)
        #expect(model.state == (grant ? .synced(added: 1, at: DayKey(iso: "2026-10-05")!.startDate(in: .gmt)) : .denied))
        let after = Form { CalendarExportRows(model: model) }.frame(width: 402, height: 874)
        #expect(ImageRenderer(content: after).cgImage != nil)
    }
}

@Test func calendarSectionIsBehindTheHapticsAndNotificationsRow() {
    let row = SettingsRoot.rows.first { $0.id == "haptics" }
    #expect(row?.sectionIds.contains(CalendarSection.sectionId) == true)
}

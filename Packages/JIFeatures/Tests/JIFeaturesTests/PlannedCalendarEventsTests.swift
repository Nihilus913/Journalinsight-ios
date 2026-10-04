import Foundation
import Testing
import JICore
@testable import JIFeatures

// W-B96 C-1 (B-96, BP-24): the served plan week → all-day calendar events. Shape = Toby's prod
// `plan.plan_session` (2026-10-04, read-only): Mon/Wed/Fri Full Upper (ids 1/2/3), Tue Interval
// Run (5), Thu Long Zone 2 (6), Sat Interval Run 2 (8), Sun Rest (7); Day 4 (4) parked = not served.
private func tobyWeek(_ start: String) -> PlanWeekOut {
    let mon = DayKey(iso: start)!
    let rows: [(Int?, String?, String?, String?, String?)] = [
        (1, "Day 1 Full Upper", "strength", "Full Upper + Zone 2 40 min", "strength"),
        (5, "Interval Run", "cardio", "Norwegian 4x4 intervals", "interval"),
        (2, "Day 2 Full Upper", "strength", "Full Upper + Zone 2 60 min", "strength"),
        (6, "Long Zone 2", "cardio", "Long Zone 2 75-90 min", "z2"),
        (3, "Day 3 Full Upper", "strength", "Full Upper + Zone 2 60 min", "strength"),
        (8, "Interval Run 2", "cardio", "Norwegian 4x4 intervals", "interval"),
        (7, "Rest", "rest", "Rest", "rest"),
    ]
    return PlanWeekOut(start: start, days: rows.enumerated().map { i, r in
        PlanWeekDayOut(date: mon.adding(days: i).iso, weekday: i, sessionId: r.0, name: r.1, sessionType: r.2,
                       prescription: r.3, type: r.4)
    })
}

@Test func calendarEventsSkipRestAndPastAndOutOfWindow() {
    let events = plannedCalendarEvents(weeks: [tobyWeek("2026-09-28"), tobyWeek("2026-10-05"), tobyWeek("2026-10-12")],
                                       today: DayKey(iso: "2026-10-04")!, daysAhead: 14)
    // window = 10-04 … 10-17: Sun 10-04 rest, then two weeks Mon–Sat.
    #expect(events.map(\.date) == ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10",
                                    "2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17"])
    #expect(events.allSatisfy { $0.isAllDay })
    #expect(!events.contains { $0.title == "Rest" })
    #expect(!events.contains { $0.date == "2026-10-18" })
}

@Test func calendarEventCarriesStableKeyTitleAndNotes() throws {
    let events = plannedCalendarEvents(weeks: [tobyWeek("2026-10-05")], today: DayKey(iso: "2026-10-04")!, daysAhead: 14)
    let tue = try #require(events.first { $0.date == "2026-10-06" })
    #expect(tue.key == "ji.plan.5.2026-10-06")
    #expect(tue.title == "Interval Run")
    #expect(tue.notes.contains("Norwegian 4x4 intervals"))
    #expect(tue.notes.contains("ji.plan.5.2026-10-06"))
    #expect(tue.notes.contains("One way"))
    #expect(tue.url == URL(string: "journalinsight://training/2026-10-06"))
}

@Test func calendarEventsNeedASessionId() {
    // a table-fallback day (no plan session) is never written — nothing stable to key it on.
    let week = PlanWeekOut(start: "2026-10-05", days: [
        PlanWeekDayOut(date: "2026-10-05", weekday: 0, sessionId: nil, name: nil, prescription: "Full Upper", type: "strength", source: "table"),
    ])
    #expect(plannedCalendarEvents(weeks: [week], today: DayKey(iso: "2026-10-04")!, daysAhead: 14).isEmpty)
}

@Test func calendarEventsDedupeOverlappingWeeks() {
    let w = tobyWeek("2026-10-05")
    let events = plannedCalendarEvents(weeks: [w, w], today: DayKey(iso: "2026-10-05")!, daysAhead: 7)
    #expect(events.count == 6)
    #expect(Set(events.map(\.key)).count == 6)
}

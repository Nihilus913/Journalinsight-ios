import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-KEYS K3: the string↔Date round-trips go through `DayKey`.
@Suite struct DayKeyAdoptionTests {
    /// Scout risk 5: a stored goal day must show as that day in the picker west of UTC.
    @Test func goalDatePickerRoundTripsWestOfUTC() {
        let ny = TimeZone(identifier: "America/New_York")!
        let d = goalDatePickerDate("2026-12-31", in: ny)!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        #expect(cal.component(.day, from: d) == 31)
        #expect(goalDatePickerISO(d, in: ny) == "2026-12-31")
        #expect(goalDatePickerDate(nil, in: ny) == nil)
        #expect(goalDatePickerDate("2026-13-01", in: ny) == nil)
    }

    @Test func targetEditorRoundTrips() {
        #expect(targetEditorDay("2026-10-25").map(targetEditorISO) == "2026-10-25")
        #expect(targetEditorDay("nope") == nil)
    }

    @Test func kpiDayDistanceAcrossDST() {
        #expect(kpiDayDistance(from: "2026-10-24", to: "2026-10-26") == 2)
        #expect(kpiDayDistance(from: "2026-10-24T08:00:00", to: "2026-10-26") == 2)
        #expect(kpiDayDistance(from: "x", to: "2026-10-26") == nil)
    }

    @Test func planWeekStartIsMonday() {
        #expect(planWeekStart("2026-10-04") == "2026-09-28")
        #expect(planWeekStart("2026-10-05") == "2026-10-05")
        #expect(planWeekStart("bad") == nil)
    }

    @Test func journalCalendarStillZurich() {
        let instant = ISO8601DateFormatter().date(from: "2026-10-03T22:30:00Z")!
        #expect(JournalCalendarZurich.isoDay(instant) == "2026-10-04")
        #expect(JournalCalendarZurich.date(fromISODay: "2026-10-25") == ISO8601DateFormatter().date(from: "2026-10-24T22:00:00Z"))
    }
}

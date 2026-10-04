import Testing
import Foundation
import JICore
@testable import JIFeatures

/// W-FIX13 F-1 (was `JournalZurichBoundaryTests`, W9.5 L3): every Journal day bucket is a
/// `DayKey` in the phone's zone (Toby D1, 2026-10-03), not a fixed Europe/Zurich calendar — the hub
/// keys its own "today" by the zone the app sends (`X-JI-TZ`), so both sides agree while travelling.
///
/// The cases are written as wall-clock times in `DayKey.zone` (whatever zone the test host runs in),
/// so they pin "the device's local day" without flipping the process-wide `NSTimeZone.default`.
@MainActor @Suite struct JournalDayKeyBoundaryTests {
    /// An instant given as wall-clock time in the phone's zone.
    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        DayKey.calendar().date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func journalCalendarIsThePhonesGregorian() {
        #expect(DayKey.calendar().timeZone == DayKey.zone)
        #expect(DayKey.calendar().identifier == .gregorian)
        #expect(DayKey(iso: "2026-08-24")?.startDate == local(2026, 8, 24, 0, 0))
        #expect(DayKey(iso: "nope") == nil)
    }

    /// The card's case: 23:30 local is still that local day for every Journal entry point.
    @Test func entryAt2330LocalBucketsIntoTheLocalDay() {
        let now = local(2026, 8, 23, 23, 30) // Sun 23 Aug, 23:30 on the phone
        let dates = ["2026-08-23", "2026-08-22", "2026-08-21"]
        let streak = JournalStreak.computeStreak(dates: dates, today: now)
        #expect(streak.current == 3)
        #expect(streak.thisWeek == 3) // Mon 17 – Sun 23
        #expect(JournalCalendar.toISO(now) == "2026-08-23")
        #expect(EntrySheetViewModel(today: now).date == "2026-08-23")
    }

    /// 00:30 local on Mon 24 Aug is the new day (and a new Mon–Sun week) on the phone.
    @Test func entryJustAfterLocalMidnightIsTheNewDay() {
        let now = local(2026, 8, 24, 0, 30)
        let dates = ["2026-08-23", "2026-08-22", "2026-08-21"]
        let streak = JournalStreak.computeStreak(dates: dates, today: now)
        #expect(streak.current == 0) // no entry on Mon 24 yet
        #expect(streak.thisWeek == 0)
        #expect(streak.best == 3)
        #expect(JournalCalendar.toISO(now) == "2026-08-24")
        #expect(JournalCalendar.scopeDays(.week, anchor: now).first == "2026-08-24")
        #expect(EntrySheetViewModel(today: now).date == "2026-08-24")
        #expect(JournalInsights.weeklyStats([], weeks: 1, today: now).first?.weekStart == "2026-08-24")
    }

    @Test func monthGridStartsOnTheLocalFirst() {
        let anchor = local(2026, 9, 1, 0, 30)
        #expect(JournalCalendar.monthGrid(month: anchor).compactMap { $0 }.first == "2026-09-01")
    }

    /// New York at 23:30 is already the next day in UTC: the key must be the local day.
    @Test func newYorkLateEveningIsTheLocalDay() {
        let ny = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ny
        let lateEvening = cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 30))!
        #expect(DayKey(date: lateEvening, in: ny).iso == "2026-10-04")
        #expect(DayKey.formatter("yyyy-MM-dd", in: ny).string(from: lateEvening) == "2026-10-04")
    }
}

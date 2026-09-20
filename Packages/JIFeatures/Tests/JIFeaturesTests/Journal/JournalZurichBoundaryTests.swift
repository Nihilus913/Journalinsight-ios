import Testing
import Foundation
@testable import JIFeatures

/// W9.5 L3 (P-journal, scout S2-3): every Journal day bucket is decided in Europe/Zurich, never in
/// the device's `Calendar.current`, so a phone in another zone agrees with the hub's day boundary.
///
/// `NSTimeZone.default` is what `TimeZone.current` / `Calendar.current` read, so flipping it is the
/// closest a unit test gets to "the device is in Los Angeles". Restored on exit; `.serialized` so the
/// two cases never overlap each other.
@MainActor @Suite(.serialized) struct JournalZurichBoundaryTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    /// An instant given as Zurich wall-clock time (CEST in August, UTC+2).
    private func zurichInstant(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zurich
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func withDeviceZone<T>(_ tz: TimeZone, _ body: () -> T) -> T {
        let saved = NSTimeZone.default
        NSTimeZone.default = tz
        defer { NSTimeZone.default = saved }
        return body()
    }

    @Test func helperIsZurichFixed() {
        #expect(JournalCalendarZurich.timeZone.identifier == "Europe/Zurich")
        #expect(JournalCalendarZurich.calendar.timeZone.identifier == "Europe/Zurich")
        #expect(JournalCalendarZurich.calendar.identifier == .gregorian)
        // 00:30 Zurich on Aug 24 is still Aug 23 in LA — the helper must not care.
        #expect(withDeviceZone(losAngeles) { JournalCalendarZurich.isoDay(zurichInstant(2026, 8, 24, 0, 30)) } == "2026-08-24")
        #expect(JournalCalendarZurich.date(fromISODay: "2026-08-24") == zurichInstant(2026, 8, 24, 0, 0))
        #expect(JournalCalendarZurich.date(fromISODay: "nope") == nil)
    }

    @Test func entryAt2330ZurichBucketsIdenticallyOnAnLADevice() {
        let now = zurichInstant(2026, 8, 23, 23, 30) // Sun 23 Aug, 23:30 Zurich
        let dates = ["2026-08-23", "2026-08-22", "2026-08-21"]
        let onZurich = withDeviceZone(zurich) { JournalStreak.computeStreak(dates: dates, today: now) }
        let onLA = withDeviceZone(losAngeles) { JournalStreak.computeStreak(dates: dates, today: now) }
        #expect(onZurich == onLA)
        #expect(onZurich.current == 3)
        #expect(onZurich.thisWeek == 3) // Mon 17 – Sun 23
        #expect(withDeviceZone(losAngeles) { JournalCalendar.toISO(now) } == "2026-08-23")
        #expect(withDeviceZone(losAngeles) { EntrySheetViewModel(today: now).date } == "2026-08-23")
    }

    /// The discriminating case: 00:30 Zurich on Mon 24 Aug is 15:30 Sun 23 Aug in LA. A device
    /// calendar would put "today" on Sunday (streak alive, week = last week); Zurich says Monday.
    @Test func entryJustAfterZurichMidnightIsTheNewDayEverywhere() {
        let now = zurichInstant(2026, 8, 24, 0, 30)
        let dates = ["2026-08-23", "2026-08-22", "2026-08-21"]
        let onZurich = withDeviceZone(zurich) { JournalStreak.computeStreak(dates: dates, today: now) }
        let onLA = withDeviceZone(losAngeles) { JournalStreak.computeStreak(dates: dates, today: now) }
        #expect(onZurich == onLA)
        #expect(onLA.current == 0) // no entry on Mon 24 yet
        #expect(onLA.thisWeek == 0) // new Mon–Sun week starts today
        #expect(onLA.best == 3)
        #expect(withDeviceZone(losAngeles) { JournalCalendar.toISO(now) } == "2026-08-24")
        #expect(withDeviceZone(losAngeles) { JournalCalendar.scopeDays(.week, anchor: now).first } == "2026-08-24")
        #expect(withDeviceZone(losAngeles) { EntrySheetViewModel(today: now).date } == "2026-08-24")
        #expect(withDeviceZone(losAngeles) { JournalInsights.weeklyStats([], weeks: 1, today: now).first?.weekStart } == "2026-08-24")
        #expect(withDeviceZone(losAngeles) { JournalPrompts.todaysPrompts(now) } == withDeviceZone(zurich) { JournalPrompts.todaysPrompts(now) })
    }

    @Test func monthGridAndRangeLabelAreZurichFixed() {
        let anchor = zurichInstant(2026, 9, 1, 0, 30) // Tue 1 Sep 00:30 Zurich = Mon 31 Aug 15:30 LA
        let onLA = withDeviceZone(losAngeles) { JournalCalendar.monthGrid(month: anchor) }
        let onZurich = withDeviceZone(zurich) { JournalCalendar.monthGrid(month: anchor) }
        #expect(onLA == onZurich)
        #expect(onLA.compactMap { $0 }.first == "2026-09-01")
        #expect(withDeviceZone(losAngeles) { JournalCalendar.rangeLabel(.month, anchor: anchor) }
            == withDeviceZone(zurich) { JournalCalendar.rangeLabel(.month, anchor: anchor) })
        #expect(withDeviceZone(losAngeles) { JournalCalendar.rangeLabel(.week, anchor: anchor) }
            == withDeviceZone(zurich) { JournalCalendar.rangeLabel(.week, anchor: anchor) })
    }
}

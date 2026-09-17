import Testing
import Foundation
import JIPersistence
@testable import JIFeatures

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
}

@Suite struct JournalCalendarScopeTests {
    // Aug 1 2026 is a Saturday.
    let sat = date(2026, 8, 1)
    let sun = date(2026, 8, 2)

    @Test func startOfWeekIsMondayFirstRegardlessOfAnchorWeekday() {
        #expect(JournalCalendar.toISO(JournalCalendar.startOfWeek(sat)) == "2026-07-27")
        #expect(JournalCalendar.toISO(JournalCalendar.startOfWeek(sun)) == "2026-07-27")
        #expect(Calendar.current.component(.weekday, from: JournalCalendar.startOfWeek(sat)) == 2) // Monday
    }

    @Test func weekScopeIsSevenConsecutiveDaysNoPadding() {
        let days = JournalCalendar.scopeDays(.week, anchor: sat)
        #expect(days.count == 7)
        #expect(days.allSatisfy { $0 != nil })
        #expect(days.first! == "2026-07-27")
        #expect(days.last! == "2026-08-02")
    }

    @Test func twoWeekScopeIsFourteenDays() {
        let days = JournalCalendar.scopeDays(.twoWeek, anchor: sat)
        #expect(days.count == 14)
        #expect(days.first! == "2026-07-27")
        #expect(days.last! == "2026-08-09")
    }

    @Test func fourWeekScopeIsTwentyEightDays() {
        let days = JournalCalendar.scopeDays(.fourWeek, anchor: sat)
        #expect(days.count == 28)
        #expect(days.first! == "2026-07-27")
        #expect(days.last! == "2026-08-23")
    }

    @Test func monthScopeDelegatesToMonthGrid() {
        #expect(JournalCalendar.scopeDays(.month, anchor: sat) == JournalCalendar.monthGrid(month: sat))
    }

    @Test func weekScopeShiftsBySevenDaysStaysMondayAligned() {
        let next = JournalCalendar.shiftAnchor(.week, anchor: sat, dir: 1)
        #expect(JournalCalendar.toISO(JournalCalendar.startOfWeek(next)) == "2026-08-03")
        let prev = JournalCalendar.shiftAnchor(.week, anchor: sat, dir: -1)
        #expect(JournalCalendar.toISO(JournalCalendar.startOfWeek(prev)) == "2026-07-20")
    }

    @Test func twoWeekScopeShiftsByFourteenDays() {
        let next = JournalCalendar.shiftAnchor(.twoWeek, anchor: sat, dir: 1)
        #expect(JournalCalendar.toISO(JournalCalendar.startOfWeek(next)) == "2026-08-10")
    }

    @Test func fourWeekScopeShiftsByTwentyEightDays() {
        let next = JournalCalendar.shiftAnchor(.fourWeek, anchor: sat, dir: 1)
        #expect(JournalCalendar.toISO(JournalCalendar.startOfWeek(next)) == "2026-08-24")
    }

    @Test func monthScopeShiftsOneCalendarMonthNormalizedToFirst() {
        let next = JournalCalendar.shiftAnchor(.month, anchor: sat, dir: 1)
        let nextComps = Calendar.current.dateComponents([.year, .month, .day], from: next)
        #expect(nextComps.year == 2026)
        #expect(nextComps.month == 9)
        #expect(nextComps.day == 1)

        let prev = JournalCalendar.shiftAnchor(.month, anchor: sat, dir: -1)
        #expect(Calendar.current.component(.month, from: prev) == 7)
    }

    @Test func monthScopeDoesNotOverflowAcrossYearBoundary() {
        let dec = date(2026, 12, 15)
        let next = JournalCalendar.shiftAnchor(.month, anchor: dec, dir: 1)
        let comps = Calendar.current.dateComponents([.year, .month], from: next)
        #expect(comps.year == 2027)
        #expect(comps.month == 1)
    }
}

@Suite struct JournalCalendarInsightsTests {
    private func e(_ id: Int64, _ date: String, _ mood: JIFeatures.Mood?, _ dur: Int = 300) -> Entry {
        Entry(id: id, date: date, ts: date + "T08:00:00", text: "x", durationSec: dur, mood: mood?.rawValue, tags: [])
    }

    @Test func monthGridIsMondayFirstAnd42Cells() {
        let g = JournalCalendar.monthGrid(month: date(2026, 8, 1)) // Aug 2026, Aug 1 = Sat
        #expect(g.count == 42)
        #expect(g.compactMap { $0 }.count == 31)
        #expect(g[0] == nil)
    }

    @Test func groupByDayMoodDistributionAvgDuration() {
        let list = [e(1, "2026-08-01", .good), e(2, "2026-08-01", .bad), e(3, "2026-08-02", .good, 600)]
        #expect(Array(JournalCalendar.groupByDay(list).keys).sorted() == ["2026-08-01", "2026-08-02"])
        #expect(JournalInsights.moodDistribution(list)[.good] == 2)
        #expect(JournalInsights.avgDurationMin(list) == 7) // (300+300+600)/3 = 400s ~ 7min
    }
}

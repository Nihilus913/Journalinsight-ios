//
//  CalendarGridTests.swift
//  JournalInsightTests
//

import Foundation
import Testing
@testable import JournalInsight

@Suite("CalendarGrid")
struct CalendarGridTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("Weekday symbols start with Monday to match ISO-8601 week dates")
    func symbolsAreMondayFirst() {
        let symbols = CalendarGrid.mondayFirstWeekdaySymbols(calendar: calendar)
        #expect(symbols.count == 7)
        #expect(symbols.first == "Mon")
        #expect(symbols.last == "Sun")
    }

    @Test("Month starting on Monday needs no leading empty cells")
    func mondayFirstOfMonthHasZeroOffset() {
        // 2026-06-01 is a Monday
        #expect(CalendarGrid.leadingEmptyCells(before: date(2026, 6, 1), calendar: calendar) == 0)
    }

    @Test("Month starting on Friday needs four leading empty cells")
    func fridayFirstOfMonthHasFourOffset() {
        // 2026-05-01 is a Friday
        #expect(CalendarGrid.leadingEmptyCells(before: date(2026, 5, 1), calendar: calendar) == 4)
    }

    @Test("Month starting on Sunday needs six leading empty cells")
    func sundayFirstOfMonthHasSixOffset() {
        // 2026-02-01 is a Sunday
        #expect(CalendarGrid.leadingEmptyCells(before: date(2026, 2, 1), calendar: calendar) == 6)
    }

    @Test("Month cells place each date under its weekday column")
    func monthCellsAlignDatesToColumns() {
        // June 2026: starts Monday, 30 days
        let dates = (1...30).map { date(2026, 6, $0) }
        let cells = CalendarGrid.monthCells(for: dates, calendar: calendar)
        #expect(cells.count == 30) // no padding needed
        // June 10 2026 is a Wednesday → index 9, column 9 % 7 == 2 (Mon=0)
        #expect(cells[9] == date(2026, 6, 10))

        // May 2026: starts Friday → 4 leading nils, May 3 (Sunday) in column 6
        let mayDates = (1...31).map { date(2026, 5, $0) }
        let mayCells = CalendarGrid.monthCells(for: mayDates, calendar: calendar)
        #expect(mayCells.count == 35)
        #expect(mayCells[0] == nil)
        #expect(mayCells[3] == nil)
        #expect(mayCells[4] == date(2026, 5, 1))
        #expect(mayCells[6] == date(2026, 5, 3))
    }

    @Test("Empty date list produces no cells")
    func emptyDatesProduceNoCells() {
        #expect(CalendarGrid.monthCells(for: [], calendar: calendar).isEmpty)
    }
}

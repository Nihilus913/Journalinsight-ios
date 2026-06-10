//
//  CalendarGrid.swift
//  JournalInsight
//
//  Pure helpers for laying journal dates into a 7-column,
//  Monday-first (ISO-8601) calendar grid.
//

import Foundation

enum CalendarGrid {
    /// Weekday header symbols in the same order as the grid columns.
    /// `shortWeekdaySymbols` is always Sunday-first; the grid dates are
    /// ISO-8601 (Monday-first), so rotate by one.
    static func mondayFirstWeekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...]) + [symbols[0]]
    }

    /// Number of empty cells before `date` so it lands under its weekday column.
    static func leadingEmptyCells(before date: Date, calendar: Calendar) -> Int {
        // .weekday is 1 = Sunday … 7 = Saturday regardless of calendar identifier.
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    /// Month dates padded with leading nils so each date sits in its weekday column.
    static func monthCells(for dates: [Date], calendar: Calendar) -> [Date?] {
        guard let first = dates.first else { return [] }
        let padding = leadingEmptyCells(before: first, calendar: calendar)
        return Array(repeating: nil, count: padding) + dates.map { $0 }
    }
}

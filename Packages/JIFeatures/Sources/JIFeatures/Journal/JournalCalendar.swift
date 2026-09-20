import Foundation
import JIPersistence

/// Ported verbatim from `mobile/src/journal/calendar.ts` + `calendarScope.ts` (E13-2).
/// `nonisolated` — see `JournalStreak`'s doc comment.
public nonisolated enum JournalCalendar {
    /// 42-cell, Monday-first month grid; `nil` cells pad before day 1 / after the last day.
    public static func monthGrid(month: Date) -> [String?] {
        let calendar = JournalCalendarZurich.calendar
        let comps = calendar.dateComponents([.year, .month], from: month)
        guard let year = comps.year, let m = comps.month,
              let first = calendar.date(from: DateComponents(year: year, month: m, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return Array(repeating: nil, count: 42) }
        let weekday = calendar.component(.weekday, from: first) // Sun=1...Sat=7
        let lead = (weekday + 5) % 7 // Mon-first padding count
        var cells: [String?] = Array(repeating: nil, count: lead)
        for d in range { cells.append(String(format: "%04d-%02d-%02d", year, m, d)) }
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    public static func groupByDay(_ entries: [Entry]) -> [String: [Entry]] {
        var out: [String: [Entry]] = [:]
        for e in entries { out[e.date, default: []].append(e) }
        return out
    }

    // MARK: Scopes (calendarScope.ts)

    public enum Scope: String, Sendable, CaseIterable, Equatable {
        case week, twoWeek = "2week", fourWeek = "4week", month
    }
    public static let SCOPES: [Scope] = [.week, .twoWeek, .fourWeek, .month]

    public static func scopeLabel(_ scope: Scope) -> String {
        switch scope {
        case .week: "Week"
        case .twoWeek: "2 Weeks"
        case .fourWeek: "4 Weeks"
        case .month: "Month"
        }
    }

    private static func dayCount(_ scope: Scope) -> Int {
        switch scope {
        case .week: 7
        case .twoWeek: 14
        case .fourWeek: 28
        case .month: 0
        }
    }

    public static func toISO(_ d: Date) -> String { JournalCalendarZurich.isoDay(d) }

    /// Monday of the week containing `d` (matches `monthGrid`'s Mon-first lead padding).
    public static func startOfWeek(_ d: Date) -> Date {
        let calendar = JournalCalendarZurich.calendar
        let weekday = calendar.component(.weekday, from: d) // Sun=1...Sat=7
        let dow = (weekday + 5) % 7 // Mon=0..Sun=6
        return calendar.date(byAdding: .day, value: -dow, to: calendar.startOfDay(for: d)) ?? d
    }

    public static func scopeDays(_ scope: Scope, anchor: Date) -> [String?] {
        if scope == .month { return monthGrid(month: anchor) }
        let n = dayCount(scope)
        let start = startOfWeek(anchor)
        let calendar = JournalCalendarZurich.calendar
        return (0..<n).map { i in
            guard let d = calendar.date(byAdding: .day, value: i, to: start) else { return nil }
            return toISO(d)
        }
    }

    /// Moves `anchor` by one scope-length in `dir` (prev = -1 / next = 1).
    public static func shiftAnchor(_ scope: Scope, anchor: Date, dir: Int) -> Date {
        let calendar = JournalCalendarZurich.calendar
        if scope == .month {
            let comps = calendar.dateComponents([.year, .month], from: anchor)
            guard let year = comps.year, let m = comps.month,
                  let base = calendar.date(from: DateComponents(year: year, month: m, day: 1)),
                  let shifted = calendar.date(byAdding: .month, value: dir, to: base)
            else { return anchor }
            return shifted
        }
        let n = dayCount(scope)
        return calendar.date(byAdding: .day, value: dir * n, to: anchor) ?? anchor
    }

    private static func fmtShort(_ iso: String, withYear: Bool) -> String {
        guard let date = JournalCalendarZurich.date(fromISODay: iso) else { return iso }
        return JournalCalendarZurich.formatter(withYear ? "MMM d, yyyy" : "MMM d").string(from: date)
    }

    /// Human-readable range label for the calendar header.
    public static func rangeLabel(_ scope: Scope, anchor: Date) -> String {
        if scope == .month {
            return JournalCalendarZurich.formatter("MMMM yyyy").string(from: anchor)
        }
        let days = scopeDays(scope, anchor: anchor).compactMap { $0 }
        guard let first = days.first, let last = days.last else { return "" }
        return "\(fmtShort(first, withYear: false)) – \(fmtShort(last, withYear: true))"
    }
}

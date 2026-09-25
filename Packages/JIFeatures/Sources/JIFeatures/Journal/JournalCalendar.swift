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

// MARK: - B-57 W1 board helpers (Journal + JournalCalendar boards, fixer f3)
//
// Pure derivations behind the Journal streak card, the check-in row, the entry rows' "n/5" and the
// JournalCalendar Entries / Average-mood cards. Every value comes from stored entries; a missing
// input stays nil and renders "—" plus a reason word (rule 5), never a zero.

/// The five journal moods on the board's 1–5 scale (Rough = 1 … Great = 5); nil for no/unknown mood.
public nonisolated func journalMoodScore(_ raw: String?) -> Int? {
    guard let raw, let mood = Mood(rawValue: raw) else { return nil }
    switch mood {
    case .great: return 5
    case .good: return 4
    case .okay: return 3
    case .bad: return 2
    case .terrible: return 1
    }
}

/// The mood a 1–5 check-in tap stands for; nil outside 1…5.
public nonisolated func journalMood(forScore score: Int) -> Mood? {
    switch score {
    case 5: .great
    case 4: .good
    case 3: .okay
    case 2: .bad
    case 1: .terrible
    default: nil
    }
}

/// One dot of the streak card's Mon–Sun row.
public nonisolated struct JournalWeekDot: Sendable, Equatable, Identifiable {
    public let id: String       // yyyy-MM-dd
    public let initial: String  // M T W T F S S
    public let written: Bool
    public let isToday: Bool
    public let isFuture: Bool
}

public nonisolated func journalWeekDots(dates: [String], today: Date) -> [JournalWeekDot] {
    let set = Set(dates.map { String($0.prefix(10)) })
    let calendar = JournalCalendarZurich.calendar
    let todayISO = JournalCalendarZurich.isoDay(today)
    let monday = JournalCalendar.startOfWeek(today)
    let initials = ["M", "T", "W", "T", "F", "S", "S"]
    return (0..<7).map { i in
        let d = calendar.date(byAdding: .day, value: i, to: monday) ?? monday
        let iso = JournalCalendarZurich.isoDay(d)
        return JournalWeekDot(id: iso, initial: initials[i], written: set.contains(iso),
                              isToday: iso == todayISO, isFuture: iso > todayISO)
    }
}

public nonisolated func journalTodayWritten(dates: [String], today: Date) -> Bool {
    let todayISO = JournalCalendarZurich.isoDay(today)
    return dates.contains { $0.hasPrefix(todayISO) }
}

/// The JournalCalendar board's segmented control.
public nonisolated enum JournalCalendarTab: String, Sendable, CaseIterable, Equatable {
    case week, month, year
    public var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }
    var periodWord: String {
        switch self {
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }
}

/// The Entries / Average-mood cards under the calendar.
public nonisolated struct JournalPeriodStats: Sendable, Equatable {
    /// Distinct days with at least one entry, up to today.
    public let entryDays: Int
    /// Days of the period that have started (the board's "of 22 days").
    public let elapsedDays: Int
    /// Mean 1–5 mood of the period's entries; nil when none carries a mood.
    public let averageMood: Double?
    /// "Up on last month" / "Down on last month" / "Steady on last month" / "No trend yet".
    public let trendWord: String
}

/// First day (inclusive) and day count of the `tab` period containing `anchor`.
nonisolated func journalPeriod(_ tab: JournalCalendarTab, anchor: Date) -> (start: Date, days: Int) {
    let calendar = JournalCalendarZurich.calendar
    switch tab {
    case .week:
        return (JournalCalendar.startOfWeek(anchor), 7)
    case .month:
        let c = calendar.dateComponents([.year, .month], from: anchor)
        let start = calendar.date(from: DateComponents(year: c.year, month: c.month, day: 1)) ?? anchor
        return (start, calendar.range(of: .day, in: .month, for: start)?.count ?? 30)
    case .year:
        let y = calendar.component(.year, from: anchor)
        let start = calendar.date(from: DateComponents(year: y, month: 1, day: 1)) ?? anchor
        return (start, calendar.range(of: .day, in: .year, for: start)?.count ?? 365)
    }
}

public nonisolated func journalShiftAnchor(_ tab: JournalCalendarTab, anchor: Date, dir: Int) -> Date {
    let calendar = JournalCalendarZurich.calendar
    switch tab {
    case .week: return calendar.date(byAdding: .day, value: 7 * dir, to: anchor) ?? anchor
    case .month: return JournalCalendar.shiftAnchor(.month, anchor: anchor, dir: dir)
    case .year: return calendar.date(byAdding: .year, value: dir, to: anchor) ?? anchor
    }
}

public nonisolated func journalCalendarTitle(_ tab: JournalCalendarTab, anchor: Date) -> String {
    switch tab {
    case .week: JournalCalendar.rangeLabel(.week, anchor: anchor)
    case .month: JournalCalendarZurich.formatter("MMMM").string(from: anchor)
    case .year: JournalCalendarZurich.formatter("yyyy").string(from: anchor)
    }
}

private nonisolated func journalPeriodISOBounds(_ tab: JournalCalendarTab, anchor: Date) -> (first: String, last: String, days: Int, start: Date) {
    let (start, days) = journalPeriod(tab, anchor: anchor)
    let end = JournalCalendarZurich.calendar.date(byAdding: .day, value: days - 1, to: start) ?? start
    return (JournalCalendarZurich.isoDay(start), JournalCalendarZurich.isoDay(end), days, start)
}

private nonisolated func journalAverageMood(_ entries: [Entry], first: String, last: String) -> Double? {
    let scores = entries.filter { $0.date >= first && $0.date <= last }.compactMap { journalMoodScore($0.mood) }
    guard !scores.isEmpty else { return nil }
    return Double(scores.reduce(0, +)) / Double(scores.count)
}

public nonisolated func journalPeriodStats(entries: [Entry], tab: JournalCalendarTab, anchor: Date, today: Date) -> JournalPeriodStats {
    let b = journalPeriodISOBounds(tab, anchor: anchor)
    let todayISO = JournalCalendarZurich.isoDay(today)
    let upTo = min(b.last, todayISO)
    let entryDays = Set(entries.map { String($0.date.prefix(10)) }.filter { $0 >= b.first && $0 <= upTo }).count
    let elapsed: Int
    if todayISO < b.first { elapsed = 0 }
    else if todayISO > b.last { elapsed = b.days }
    else {
        let t = JournalCalendarZurich.date(fromISODay: todayISO) ?? today
        elapsed = (JournalCalendarZurich.calendar.dateComponents([.day], from: b.start, to: t).day ?? 0) + 1
    }
    let average = journalAverageMood(entries, first: b.first, last: b.last)
    let prev = journalPeriodISOBounds(tab, anchor: journalShiftAnchor(tab, anchor: b.start, dir: -1))
    let previous = journalAverageMood(entries, first: prev.first, last: prev.last)
    let trend: String
    if let average, let previous {
        let delta = average - previous
        trend = delta > 0.25 ? "Up on last \(tab.periodWord)"
            : delta < -0.25 ? "Down on last \(tab.periodWord)" : "Steady on last \(tab.periodWord)"
    } else {
        trend = "No trend yet"
    }
    return JournalPeriodStats(entryDays: entryDays, elapsedDays: elapsed, averageMood: average, trendWord: trend)
}

/// "4.0" for a mean mood, "—" when there is none (rule 5).
public nonisolated func journalAverageMoodText(_ average: Double?) -> String {
    guard let average else { return "—" }
    return String(format: "%.1f", average)
}

/// Distinct entry days per month (index 0 = January) — the Year tab's grid.
public nonisolated func journalYearMonthCounts(dates: [String], year: Int) -> [Int] {
    var counts = Array(repeating: 0, count: 12)
    for iso in Set(dates.map { String($0.prefix(10)) }) {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, p[0] == year, (1...12).contains(p[1]) else { continue }
        counts[p[1] - 1] += 1
    }
    return counts
}

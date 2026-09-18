#if canImport(HealthKit)
import Foundation

/// The calendar grid a T2 (`HealthKitProvider`) read runs over: `windowDays` consecutive local
/// days ending on the day that contains `now`, plus the `[start, end)` instant range those days
/// span.
///
/// Pure value type with an **injected** `Calendar` — the provider decides the time zone once
/// (device-local by default) and every bucketing decision downstream reads it from here, so no
/// assembler ever reaches for `Calendar.current`/`TimeZone.current` on its own. ISO day keys are
/// formatted arithmetically from `DateComponents`, never via `DateFormatter`, so the key is
/// locale- and calendar-identifier-independent (`ar_SA`, Buddhist, etc. would otherwise render
/// a different string for the same instant).
public struct HKSampleWindow: Sendable, Equatable {
    /// Local midnight of the window's first day.
    public let start: Date
    /// Exclusive upper bound: local midnight of the day AFTER the window's last day.
    public let end: Date
    /// `"YYYY-MM-DD"` keys, ascending, `windowDays` of them.
    public let days: [String]
    /// The calendar (time zone included) every bucketing decision in this window uses.
    public let calendar: Calendar

    /// `windowDays` is clamped to at least 1 — a zero/negative window is a caller bug, and an
    /// empty grid would silently return "no recovery data" instead of failing loudly.
    public init(windowDays: Int, now: Date, calendar: Calendar) {
        let count = max(1, windowDays)
        self.calendar = calendar
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? today
        self.start = first
        self.end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        var keys: [String] = []
        keys.reserveCapacity(count)
        var cursor = first
        for _ in 0..<count {
            keys.append(Self.isoDay(cursor, calendar: calendar))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        self.days = keys
    }

    /// True when `date` falls inside `[start, end)`.
    public func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// The `"YYYY-MM-DD"` bucket `date` belongs to, or `nil` when it is outside the window.
    public func dayKey(for date: Date) -> String? {
        guard contains(date) else { return nil }
        return Self.isoDay(date, calendar: calendar)
    }

    /// `"YYYY-MM-DD"` for the local day containing `date`.
    public static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year = c.year ?? 0, month = c.month ?? 0, day = c.day ?? 0
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        let padding = width - digits.count
        return padding > 0 ? String(repeating: "0", count: padding) + digits : digits
    }
}
#endif

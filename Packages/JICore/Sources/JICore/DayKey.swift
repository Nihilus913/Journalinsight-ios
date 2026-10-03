import Foundation

/// The one calendar-day key (W-KEYS K1, audit P6): a `yyyy-MM-dd` string plus the arithmetic
/// that used to be re-implemented with `ISO8601Format().prefix(10)` (a UTC day) and ad-hoc
/// `DateFormatter`s across the app.
///
/// **Zone (Toby D1, 2026-10-03):** the day follows the time zone set on the phone —
/// `TimeZone.current` — so days, the morning window and the training schedule move with Toby
/// when he travels. The hub keys its own "today" by the same zone (the app sends `X-JI-TZ`, HT
/// `app/shared/days.py`). Every zone-dependent entry point takes `in zone:` (default
/// `DayKey.zone`) so tests inject one (`Europe/Zurich` for the card's cases).
///
/// Day arithmetic (`adding(days:)`, `days(to:)`, `mondayOfWeek`) is calendar-only and
/// zone-free: it never steps by `86_400` seconds, so DST nights cannot skip or repeat a day.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// `yyyy-MM-dd`.
    public let iso: String

    /// The production zone: the phone's current time zone (D1).
    public static var zone: TimeZone { .current }

    /// Gregorian in UTC — only used for zone-free day arithmetic on the key's components.
    private static let civil: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    private init(y: Int, m: Int, d: Int) {
        iso = String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// The day `now` falls on in `zone`.
    public static func today(now: Date = Date(), in zone: TimeZone = DayKey.zone) -> DayKey {
        DayKey(date: now, in: zone)
    }

    /// The calendar day containing `date` in `zone`.
    public init(date: Date, in zone: TimeZone = DayKey.zone) {
        let c = Self.calendar(zone).dateComponents([.year, .month, .day], from: date)
        self.init(y: c.year ?? 0, m: c.month ?? 0, d: c.day ?? 0)
    }

    /// Parses the first 10 characters as `yyyy-MM-dd` (so a full ISO timestamp is accepted);
    /// `nil` unless they name a real calendar date (`2026-13-01`, `2026-02-30` → nil).
    public init?(iso: String) {
        let head = Array(iso.prefix(10))
        guard head.count == 10, head[4] == "-", head[7] == "-" else { return nil }
        let digits = head.enumerated().filter { $0.offset != 4 && $0.offset != 7 }.map(\.element)
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let y = Int(String(head[0..<4])), let m = Int(String(head[5..<7])), let d = Int(String(head[8..<10])),
              let date = Self.civil.date(from: DateComponents(year: y, month: m, day: d))
        else { return nil }
        let back = Self.civil.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        self.init(y: y, m: m, d: d)
    }

    /// Noon UTC of this day — a zone-free anchor for calendar arithmetic.
    private var civilDate: Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return Self.civil.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!
    }

    /// `n` calendar days later (negative = earlier).
    public func adding(days n: Int) -> DayKey {
        DayKey(date: Self.civil.date(byAdding: .day, value: n, to: civilDate)!, in: Self.civil.timeZone)
    }

    /// Whole calendar days from `self` to `other` (negative when `other` is earlier).
    public func days(to other: DayKey) -> Int {
        Self.civil.dateComponents([.day], from: civilDate, to: other.civilDate).day ?? 0
    }

    /// Midnight of this day in `zone`.
    public func startDate(in zone: TimeZone) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return Self.calendar(zone).date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }

    /// Midnight of this day in the phone's zone.
    public var startDate: Date { startDate(in: Self.zone) }

    /// The Monday of this day's Mon–Sun week.
    public var mondayOfWeek: DayKey {
        let weekday = Self.civil.component(.weekday, from: civilDate) // 1 = Sunday … 7 = Saturday
        return adding(days: -((weekday + 5) % 7))
    }

    public static func < (a: DayKey, b: DayKey) -> Bool { a.iso < b.iso }

    public var description: String { iso }

    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let k = DayKey(iso: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not yyyy-MM-dd: \(s)"))
        }
        self = k
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

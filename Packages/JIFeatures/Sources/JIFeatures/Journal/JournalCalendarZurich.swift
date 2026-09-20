import Foundation

/// The Journal's one calendar (W9.5 L3, P-journal — scout S2-3).
///
/// Journal day buckets (`entries.date`, streaks, Mon–Sun weeks, the month grid) must agree with the
/// hub's day boundary, which is Europe/Zurich by contract (W2h). Reading the device's current calendar
/// instead let a device in another zone silently disagree — an entry at 00:30 Zurich became "yesterday" in
/// Los Angeles, breaking the streak. Every Journal file goes through this enum now; nothing in
/// `Journal/` reads the device calendar or `TimeZone.current`.
///
/// Mirrors `JIHealthKit/BackloadDateParsing.zurich` by copy (four lines): JIFeatures does not
/// import JIHealthKit for a time zone constant. `nonisolated` — JIFeatures defaults to `MainActor`
/// (memory `project_jidesign_isolation_gotcha`) and this is pure date arithmetic used from tests.
public nonisolated enum JournalCalendarZurich {
    public static let timeZone = TimeZone(identifier: "Europe/Zurich")!

    /// Gregorian, Zurich-fixed. `Calendar` is a value type, so callers may copy and tweak it.
    public static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }()

    /// `yyyy-MM-dd` of the Zurich calendar day containing `d`.
    public static func isoDay(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Zurich midnight for a `yyyy-MM-dd` string; `nil` when the string is not three integers.
    public static func date(fromISODay iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// A `DateFormatter` for `format` that renders in Zurich (labels for Zurich-midnight dates
    /// would otherwise print the previous day on a device west of Europe).
    public static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }
}

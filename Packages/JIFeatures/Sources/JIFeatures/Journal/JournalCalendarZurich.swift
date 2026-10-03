import Foundation
import JICore

/// The Journal's one calendar (W9.5 L3, P-journal — scout S2-3).
///
/// W-KEYS K1: the day arithmetic delegates to `JICore.DayKey` (Zurich injected as the zone).
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
        DayKey(date: d, in: timeZone).iso
    }

    /// Zurich midnight for a `yyyy-MM-dd` string; `nil` when it is not a valid `DayKey`.
    public static func date(fromISODay iso: String) -> Date? {
        DayKey(iso: iso)?.startDate(in: timeZone)
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

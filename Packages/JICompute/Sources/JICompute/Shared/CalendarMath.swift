/// Timezone-free calendar math on ISO `"YYYY-MM-DD"` strings.
///
/// Transliterated from the RN oracle `mobile/src/compute/shared/date.ts`
/// (frozen v1.18.2).
///
/// Parity rule (spec: 2026-08-23-ts-compute-parity-port): compute code never
/// touches the device's local timezone — weekday selection and consecutive-
/// morning logic must give the same answer on the phone as the Python pipeline
/// gives on the Mac. The TS oracle achieves this with `Date.UTC` on parsed
/// parts; Swift has no timezone-free `Date`, so we do the civil↔serial-day
/// conversion in pure integer arithmetic instead (Howard Hinnant's
/// `days_from_civil` / `civil_from_days`, valid for any proleptic Gregorian
/// date). Nothing here touches `Calendar`, `TimeZone`, `Locale` or `Date` —
/// per XC `CLAUDE.md` rule 8 those are banned from `JICompute`.
public nonisolated enum CalendarMath {
    /// Errors a caller can get from the strict parsers.
    public enum Error: Swift.Error, Equatable, Sendable {
        case malformedISODate(String)
    }

    // MARK: - Serial days (days since 1970-01-01)

    /// Days from 1970-01-01 to the given proleptic-Gregorian civil date.
    public static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                       // [0, 399]
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1 // [0, 365]
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy               // [0, 146096]
        return era * 146_097 + doe - 719_468
    }

    /// Inverse of `daysFromCivil`.
    public static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097                                   // [0, 146096]
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365 // [0, 399]
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)             // [0, 365]
        let mp = (5 * doy + 2) / 153                                  // [0, 11]
        let d = doy - (153 * mp + 2) / 5 + 1                          // [1, 31]
        let m = mp + (mp < 10 ? 3 : -9)                               // [1, 12]
        return (y + (m <= 2 ? 1 : 0), m, d)
    }

    // MARK: - ISO parsing / rendering

    /// Parse `"YYYY-MM-DD"` into days since 1970-01-01.
    ///
    /// Strict: the string must be exactly ten ASCII characters with dashes at
    /// index 4 and 7 and digits everywhere else. The TS oracle relies on
    /// `Number(...)` of fixed slices and would silently yield `NaN`; here a
    /// malformed date is an error, never a wrong answer.
    public static func parseDays(_ iso: String) throws -> Int {
        let s = Array(iso.utf8)
        guard s.count == 10, s[4] == UInt8(ascii: "-"), s[7] == UInt8(ascii: "-") else {
            throw Error.malformedISODate(iso)
        }
        func digits(_ range: Range<Int>) throws -> Int {
            var value = 0
            for i in range {
                let c = s[i]
                guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") else { throw Error.malformedISODate(iso) }
                value = value * 10 + Int(c - UInt8(ascii: "0"))
            }
            return value
        }
        let y = try digits(0..<4)
        let m = try digits(5..<7)
        let d = try digits(8..<10)
        guard (1...12).contains(m), (1...31).contains(d) else { throw Error.malformedISODate(iso) }
        return daysFromCivil(year: y, month: m, day: d)
    }

    /// Render days since 1970-01-01 as `"YYYY-MM-DD"`.
    public static func isoString(fromDays days: Int) -> String {
        let (y, m, d) = civilFromDays(days)
        return pad(y, 4) + "-" + pad(m, 2) + "-" + pad(d, 2)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let negative = value < 0
        let digits = String(negative ? -value : value)
        let body = String(repeating: "0", count: max(0, width - digits.count)) + digits
        return negative ? "-" + body : body
    }

    // MARK: - Oracle surface (mirrors shared/date.ts)

    /// Python `date.weekday()`: Monday = 0 … Sunday = 6.
    public static func isoWeekday(_ iso: String) throws -> Int {
        weekday(fromDays: try parseDays(iso))
    }

    /// Python `date.weekday()` from a serial day. 1970-01-01 was a Thursday
    /// (Python weekday 3), which anchors the modulus.
    public static func weekday(fromDays days: Int) -> Int {
        (((days % 7) + 7) % 7 + 3) % 7
    }

    /// `iso + n` days (`n` may be negative).
    public static func addDays(_ iso: String, _ n: Int) throws -> String {
        isoString(fromDays: try parseDays(iso) + n)
    }

    /// Whole days from `b` to `a`: `(a - b)`, like Python `(date_a - date_b).days`.
    public static func diffDays(_ a: String, _ b: String) throws -> Int {
        try parseDays(a) - parseDays(b)
    }
}

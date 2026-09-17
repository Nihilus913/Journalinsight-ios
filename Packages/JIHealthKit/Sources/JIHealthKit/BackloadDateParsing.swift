import Foundation

/// Shared date parsing for the hub's two wire formats: full ISO-8601-with-offset timestamps
/// (`sleep`/`workouts` start/end) and bare `YYYY-MM-DD` local dates (`rhr`/`steps`/`energy`/
/// `vo2max`), interpreted in the hub's own zone (Europe/Zurich, per the W2h contract note).
enum BackloadDateParsing {
    static let zurich = TimeZone(identifier: "Europe/Zurich")!

    private static var isoWithFraction: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
    private static var iso: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Parses an offset timestamp like `2025-06-01T22:30:00+02:00`.
    static func timestamp(_ s: String) -> Date? {
        isoWithFraction.date(from: s) ?? iso.date(from: s)
    }

    private static var zurichCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zurich
        return cal
    }

    /// The day's [00:00:00, 23:59:59] bounds in Europe/Zurich, for a bare `YYYY-MM-DD` date string.
    static func dayBounds(_ dateString: String) -> (start: Date, end: Date)? {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let cal = zurichCalendar
        guard let start = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return nil }
        guard let end = cal.date(byAdding: DateComponents(hour: 23, minute: 59, second: 59), to: start) else { return nil }
        return (start, end)
    }
}

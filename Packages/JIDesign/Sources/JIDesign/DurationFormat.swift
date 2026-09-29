import Foundation

/// W-SSOT-1 SS-6 (audit 01-P9): the one place duration strings are built. Each style keeps the
/// exact output of the inline copy it replaced, so no screen changes wording.
public nonisolated enum DurationFormat {
    /// "7h 24m" — whole hours and minutes, truncated (Sleep card).
    public static func hoursMinutes(seconds: Double) -> String {
        let s = Int(seconds)
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    /// "7 h 24" — rounded to the minute, minutes zero-padded (Recovery sleep tiles).
    public static func hoursPaddedMinutes(seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return "\(m / 60) h \(String(format: "%02d", m % 60))"
    }

    /// "10:00", "0:45" — minutes, colon, zero-padded seconds (workout steps, coach elapsed).
    public static func clock(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "12 min" — whole minutes, floored.
    public static func minutes(seconds: Int) -> String { "\(seconds / 60) min" }
}

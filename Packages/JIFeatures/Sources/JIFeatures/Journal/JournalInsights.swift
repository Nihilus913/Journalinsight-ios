import Foundation
import JIPersistence

/// Ported verbatim from `mobile/src/journal/insights.ts`. `nonisolated` — see `JournalStreak`'s
/// doc comment.
public nonisolated enum JournalInsights {
    public static func moodDistribution(_ entries: [Entry]) -> [Mood: Int] {
        var out = Dictionary(uniqueKeysWithValues: MOODS.map { ($0, 0) })
        for e in entries {
            guard let mood = e.mood.flatMap(Mood.init(rawValue:)) else { continue }
            out[mood, default: 0] += 1
        }
        return out
    }

    public static func entryCount(_ entries: [Entry]) -> Int { entries.count }

    public static func avgDurationMin(_ entries: [Entry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let total = entries.reduce(0) { $0 + $1.durationSec }
        let avgSec = Double(total) / Double(entries.count)
        return Int((avgSec / 60).rounded())
    }

    // MARK: Time-of-day distribution — bucket boundaries ported verbatim from Xcode's
    // StreakCalculator.preferredTimeOfDay (<7 Early Morning, 7-11 Morning, 12-16 Afternoon,
    // 17-20 Evening, else Night), but per-entry (a histogram), not averaged first.
    public enum TimeOfDayBucket: String, Sendable, CaseIterable, Equatable {
        case earlyMorning = "Early Morning"
        case morning = "Morning"
        case afternoon = "Afternoon"
        case evening = "Evening"
        case night = "Night"
    }
    public static let TIME_OF_DAY_BUCKETS: [TimeOfDayBucket] = [.earlyMorning, .morning, .afternoon, .evening, .night]

    /// `ts` is an ISO-8601 local timestamp string (`entries.ts`, written with `Date().ISO8601Format()`
    /// — no `Z`/offset, so it round-trips through `ISO8601DateFormatter` with `.withInternetDateTime`
    /// disabled). Falls back to hour 0 if the string can't be parsed at all.
    public static func timeOfDayBucket(_ ts: String) -> TimeOfDayBucket {
        let hour = hourOfDay(ts)
        if hour < 7 { return .earlyMorning }
        if hour < 12 { return .morning }
        if hour < 17 { return .afternoon }
        if hour < 21 { return .evening }
        return .night
    }

    private static func hourOfDay(_ ts: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: ts)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: ts)
        }
        if date == nil {
            // No zone/offset in the string (e.g. "2026-08-01T06:00:00") — parse as a local time.
            let parts = ts.split(separator: "T")
            if parts.count == 2 {
                let timePart = parts[1].split(separator: ":")
                if let h = timePart.first, let hour = Int(h) { return hour }
            }
        }
        guard let date else { return 0 }
        return Calendar.current.component(.hour, from: date)
    }

    public static func timeOfDayDistribution(_ entries: [Entry]) -> [TimeOfDayBucket: Int] {
        var out = Dictionary(uniqueKeysWithValues: TIME_OF_DAY_BUCKETS.map { ($0, 0) })
        for e in entries { out[timeOfDayBucket(e.ts), default: 0] += 1 }
        return out
    }

    public static func preferredTimeOfDay(_ entries: [Entry]) -> TimeOfDayBucket? {
        guard !entries.isEmpty else { return nil }
        let dist = timeOfDayDistribution(entries)
        return TIME_OF_DAY_BUCKETS.reduce(TIME_OF_DAY_BUCKETS[0]) { best, bucket in
            (dist[bucket] ?? 0) > (dist[best] ?? 0) ? bucket : best
        }
    }

    public static func longestSessionSec(_ entries: [Entry]) -> Int {
        entries.reduce(0) { max($0, $1.durationSec) }
    }

    // MARK: Weekly charts

    public struct WeekBucket: Sendable, Equatable {
        public var weekStart: String
        public var count: Int
        public var avgDurationMin: Int
    }

    private static func addDaysISO(_ iso: String, _ n: Int) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return iso }
        let comps = DateComponents(year: parts[0], month: parts[1], day: parts[2] + n)
        let calendar = Calendar.current
        guard let date = calendar.date(from: comps) else { return iso }
        let out = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", out.year ?? 0, out.month ?? 0, out.day ?? 0)
    }

    private static func mondayOfWeek(_ dateISO: String) -> String {
        let parts = dateISO.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return dateISO }
        let weekday = Calendar.current.component(.weekday, from: date) // Sun=1...Sat=7
        let dow = (weekday + 5) % 7 // Mon=0
        return addDaysISO(dateISO, -dow)
    }

    public static func weeklyStats(_ entries: [Entry], weeks: Int, today: Date) -> [WeekBucket] {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: today)
        let todayISO = String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        let thisMonday = mondayOfWeek(todayISO)
        let starts = (0..<weeks).map { addDaysISO(thisMonday, -7 * (weeks - 1 - $0)) }

        var totals: [String: (count: Int, totalSec: Int)] = Dictionary(uniqueKeysWithValues: starts.map { ($0, (0, 0)) })
        for e in entries {
            let bucket = mondayOfWeek(e.date)
            guard totals[bucket] != nil else { continue }
            totals[bucket]!.count += 1
            totals[bucket]!.totalSec += e.durationSec
        }

        return starts.map { weekStart in
            let b = totals[weekStart] ?? (0, 0)
            let avg = b.count > 0 ? Int((Double(b.totalSec) / Double(b.count) / 60).rounded()) : 0
            return WeekBucket(weekStart: weekStart, count: b.count, avgDurationMin: avg)
        }
    }
}

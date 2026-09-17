import Foundation

/// Ported verbatim from `mobile/src/journal/streak.ts`. `nonisolated` (JIFeatures defaults to
/// `MainActor` isolation — CONTEXT §3 / memory `project_jidesign_isolation_gotcha`) since this is
/// pure date arithmetic with no UI state, called from both the view model and plain unit tests.
public nonisolated enum JournalStreak {
    public static let MILESTONES = [7, 14, 30, 50, 100, 200, 365]

    public struct Stats: Sendable, Equatable {
        public var current: Int
        public var best: Int
        public var thisWeek: Int
        public var nextMilestone: Int?
    }

    private static func dayKey(_ s: String) -> String { String(s.prefix(10)) }

    /// Local calendar-day arithmetic — `date` here is always a `yyyy-MM-dd` wall-clock day, so this
    /// intentionally uses the device's current calendar/time zone (matches RN's local `Date`
    /// getters), unlike `JICompute` (W6), which is explicitly forbidden `Calendar.current`.
    private static func addDays(_ iso: String, _ n: Int) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return iso }
        var comps = DateComponents(year: parts[0], month: parts[1], day: parts[2] + n)
        let calendar = Calendar.current
        guard let date = calendar.date(from: comps) else { return iso }
        comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? parts[0], comps.month ?? parts[1], comps.day ?? parts[2])
    }

    private static func localISO(_ d: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    public static func computeStreak(dates: [String], today: Date) -> Stats {
        let set = Set(dates.map(dayKey))
        let todayISO = localISO(today)

        var current = 0
        if set.contains(todayISO) {
            var cur = todayISO
            while set.contains(cur) {
                current += 1
                cur = addDays(cur, -1)
            }
        }

        let sorted = set.sorted()
        var best = 0, run = 0
        var prev: String?
        for day in sorted {
            run = (prev != nil && addDays(prev!, 1) == day) ? run + 1 : 1
            best = max(best, run)
            prev = day
        }

        // Current Mon–Sun week.
        let weekday = Calendar.current.component(.weekday, from: today) // Sun=1...Sat=7
        let dow = (weekday + 5) % 7 // Mon=0
        let monday = addDays(todayISO, -dow)
        let sunday = addDays(monday, 6)
        let thisWeek = set.filter { $0 >= monday && $0 <= sunday }.count

        let nextMilestone = MILESTONES.first { $0 > current }
        return Stats(current: current, best: best, thisWeek: thisWeek, nextMilestone: nextMilestone)
    }

    /// E13-3 — the fix for the "Swift re-fires every mount" celebration bug (see RN's doc comment
    /// in `streak.ts`). Returns the highest milestone newly reached since `lastCelebrated`, or
    /// `nil` when there's nothing new to celebrate.
    public static func nextUnseenMilestone(current: Int, lastCelebrated: Int?) -> Int? {
        let floor = lastCelebrated ?? 0
        let crossed = MILESTONES.filter { $0 > floor && $0 <= current }
        return crossed.last
    }
}

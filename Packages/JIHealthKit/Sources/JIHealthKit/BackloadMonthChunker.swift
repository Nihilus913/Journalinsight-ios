import Foundation
import JICore

/// Splits a `BackloadRange` into calendar-month chunks (Europe/Zurich), in order, each ≤ 31 days
/// so a single hub request never exceeds the contract's 92-day cap. `resumeFrom` (the persisted
/// cursor — the last successfully-written day) advances the start past what's already done.
///
/// `HealthKitBackloader` fetches every chunk twice — a *daily pass* (`dailyPassKinds`) then a
/// *dense pass* (`densePassKinds`), per the v2 contract note ("dense kinds chunk by ≤31 days:
/// split the run into a daily pass then a dense pass per month"). Chunk boundaries are shared
/// between both passes rather than computed separately, because a calendar month is never longer
/// than 31 days — which already satisfies the hub's `MAX_RANGE_DAYS_DENSE` cap for the dense pass
/// (`app/vitals/backload.py`), so there is nothing narrower to compute.
enum BackloadMonthChunker {
    struct Chunk: Sendable, Equatable {
        var from: Date
        var to: Date
    }

    /// Kinds requested in the daily pass: cheap daily aggregates. Deliberately excludes `sleep`
    /// (moved to `densePassKinds`, see its doc comment) and every genuinely-dense series.
    static let dailyPassKinds: Set<String> = [
        "rhr", "steps", "energy", "vo2max", "workouts", "daily_resp", "daily_spo2",
        "floors", "distance", // W9 (B-30 P5), hub contract v3 (HT e7720ff)
    ]

    /// Kinds requested in the dense pass. `sleep` rides along with `stages` — the hub only nests
    /// stage intervals inside `sleep[]` entries when `sleep` itself is requested
    /// (`app/vitals/backload.py:fetch_backload`, `"stages" in kinds` populates `stages_by_date`,
    /// but only entries built while `"sleep" in kinds` attach it) — so fetching `stages` alone
    /// would come back with an empty `sleep` array and every stage interval silently discarded.
    /// The other names are the hub's own `DENSE_KINDS` (W11 adds the per-workout `workout_hr` /
    /// `workout_routes`, contract v4). Requesting any of them caps the range at
    /// `MAX_RANGE_DAYS_DENSE` (31 days), which every chunk here already satisfies.
    static let densePassKinds: Set<String> = [
        "sleep", "stages", "heart_rate", "respiration", "spo2", "hrv_readings", "step_buckets",
        "workout_hr", "workout_routes", // W11 (B-30 P4), hub contract v4
    ]

    private static var zurichCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BackloadDateParsing.zurich
        return cal
    }

    static func chunks(for range: BackloadRange, resumeFrom cursor: Date?) -> [Chunk] {
        let cal = zurichCalendar
        var start = range.from
        if let cursor, let next = cal.date(byAdding: .day, value: 1, to: cursor) {
            start = max(start, next)
        }
        guard start <= range.to else { return [] }

        var result: [Chunk] = []
        var cursorDate = start
        while cursorDate <= range.to {
            let comps = cal.dateComponents([.year, .month], from: cursorDate)
            guard let monthStart = cal.date(from: comps),
                  let nextMonthStart = cal.date(byAdding: .month, value: 1, to: monthStart),
                  let monthEnd = cal.date(byAdding: .day, value: -1, to: nextMonthStart) else { break }
            let chunkTo = min(monthEnd, range.to)
            result.append(Chunk(from: cursorDate, to: chunkTo))
            guard let next = cal.date(byAdding: .day, value: 1, to: chunkTo) else { break }
            cursorDate = next
        }
        return result
    }
}

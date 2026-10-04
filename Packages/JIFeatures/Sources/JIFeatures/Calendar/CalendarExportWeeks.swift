import Foundation
import JICore
import JIPersistence

// W-B96 C-5 (B-96): the weeks the calendar export reads — the hub's served `/planning/week` for
// every Monday the 14-day window touches (up to three), each cached so a later foreground
// without the hub still writes from the last answer (B-52 offline-first).

public nonisolated func calendarExportCacheKey(_ monday: String) -> String { "calendar.planWeek.\(monday)" }

/// The Mondays of the weeks [today, today + daysAhead) touches.
public nonisolated func calendarExportMondays(today: DayKey, daysAhead: Int = calendarExportDaysAhead) -> [DayKey] {
    let first = today.mondayOfWeek, last = today.adding(days: max(daysAhead - 1, 0)).mondayOfWeek
    return stride(from: 0, through: first.days(to: last), by: 7).map { first.adding(days: $0) }
}

/// `fetch` = `TrainingProviding.planWeek(start:)`; nil (no hub provider) → cache only.
public func calendarExportWeeks(today: DayKey, cache: OfflineCache,
                                fetch: ((String) async throws -> PlanWeekOut)?) async -> [PlanWeekOut] {
    var out: [PlanWeekOut] = []
    for monday in calendarExportMondays(today: today) {
        let key = calendarExportCacheKey(monday.iso)
        if let fetch, let week = try? await fetch(monday.iso) {
            try? cache.put(key, week)
            out.append(week)
        } else if let hit = try? cache.get(key, as: PlanWeekOut.self) {
            out.append(hit.value)
        }
    }
    return out
}

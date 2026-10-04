import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-B96 C-5 (B-96): the 14-day window's weeks come from the hub, and from the cache when the hub
// is unreachable (B-52).
@Test func calendarMondaysCoverTheWindow() {
    #expect(calendarExportMondays(today: DayKey(iso: "2026-10-04")!).map(\.iso) == ["2026-09-28", "2026-10-05", "2026-10-12"])
    #expect(calendarExportMondays(today: DayKey(iso: "2026-10-05")!).map(\.iso) == ["2026-10-05", "2026-10-12"])
}

@Test @MainActor func calendarWeeksFallBackToTheCache() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let today = DayKey(iso: "2026-10-05")!
    var asked: [String] = []
    let live = await calendarExportWeeks(today: today, cache: cache) { start in
        asked.append(start); return PlanWeekOut(start: start, days: [])
    }
    #expect(asked == ["2026-10-05", "2026-10-12"])
    #expect(live.map(\.start) == ["2026-10-05", "2026-10-12"])
    struct Offline: Error {}
    let offline = await calendarExportWeeks(today: today, cache: cache) { _ in throw Offline() }
    #expect(offline.map(\.start) == ["2026-10-05", "2026-10-12"])
    let none = await calendarExportWeeks(today: today, cache: OfflineCache(db: try AppDatabase.inMemory()), fetch: nil)
    #expect(none.isEmpty)
}

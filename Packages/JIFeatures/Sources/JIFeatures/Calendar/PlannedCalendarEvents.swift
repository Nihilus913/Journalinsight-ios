import Foundation
import JICore

// W-B96 C-1 (B-96, BP-24): what JournalInsight writes into the iPhone Calendar. Toby 2026-10-04:
// one way, write-only, ALL-DAY events (default; he may override with a usual start time later).

/// One planned session as a calendar event. `key` is stable per (plan session, date) so the
/// write ledger never adds the same session twice (write-only access cannot read events back).
public nonisolated struct PlannedCalendarEvent: Sendable, Equatable, Identifiable {
    public var key: String
    public var date: String
    public var title: String
    public var notes: String
    public var isAllDay: Bool
    public var url: URL?
    public var id: String { key }
}

/// The fixed rolling window (days from today, today included). A "Days ahead" picker is Later.
public nonisolated let calendarExportDaysAhead = 14

/// Served `/planning/week` answers → events for dates in [today, today + daysAhead). Rest days,
/// days without a plan session (table fallback) and past days are never written; overlapping
/// weeks are de-duplicated by key, output sorted by date.
public nonisolated func plannedCalendarEvents(weeks: [PlanWeekOut], today: DayKey, daysAhead: Int) -> [PlannedCalendarEvent] {
    let end = today.adding(days: daysAhead)
    var seen = Set<String>()
    var out: [PlannedCalendarEvent] = []
    for day in weeks.flatMap(\.days) {
        guard let sid = day.sessionId, let d = DayKey(iso: day.date), d >= today, d < end else { continue }
        if day.type == "rest" || day.sessionType == "rest" { continue }
        let key = "ji.plan.\(sid).\(day.date)"
        guard seen.insert(key).inserted else { continue }
        let title = day.name ?? day.prescription ?? "Training"
        var lines: [String] = []
        if let p = day.prescription, p != title { lines.append(p) }
        lines.append("One way from JournalInsight — edits here do not change the plan.")
        lines.append(key)
        out.append(PlannedCalendarEvent(key: key, date: day.date, title: title, notes: lines.joined(separator: "\n"),
                                        isAllDay: true, url: URL(string: "journalinsight://training/\(day.date)")))
    }
    return out.sorted { ($0.date, $0.key) < ($1.date, $1.key) }
}

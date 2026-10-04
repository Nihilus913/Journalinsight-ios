import Foundation

/// W-B92 C-3 (Bevel gap BP-1) — `GET /api/v1/training/calendar?month=YYYY-MM` (HT
/// `app/training/calendar.py`): every day of a month, planned (the hub's daily snapshot, else its
/// schedule) vs done (the hub's ONE completion rule), as a cell `state` + the month's counts.
/// Toby 2026-10-04: Q1 partial never counts as done (`summary.done` is the credited count);
/// a past owed day the activity data has not reached is `.unknown`, never `.missed`.
/// Snake_case keys via `JSON.decoder`.
public nonisolated struct TrainingCalendarMonth: Codable, Sendable, Equatable {
    public var month: String
    public var today: String
    /// MAX(core.activity.date) on the hub — days after it are `.unknown`. nil = no activity yet.
    public var syncedThrough: String?
    public var days: [TrainingCalendarDay]
    public var summary: TrainingCalendarSummary

    public init(month: String, today: String, syncedThrough: String?, days: [TrainingCalendarDay], summary: TrainingCalendarSummary) {
        self.month = month; self.today = today; self.syncedThrough = syncedThrough; self.days = days; self.summary = summary
    }
}

public nonisolated struct TrainingCalendarDay: Codable, Sendable, Equatable, Identifiable {
    public enum State: String, Codable, Sendable, Equatable, CaseIterable {
        case done, partial, missed, unknown, planned, rest

        /// A state a newer hub sends that this build does not know reads as `.unknown` — never
        /// judged as missed.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw) ?? .unknown
        }
    }

    public var date: String
    public var planned: TrainingCalendarPlanned
    public var state: State
    /// The hub's completion status (`done` | `partial` | `open`); nil for future days / offline.
    public var status: String?
    public var credited: Bool
    public var activities: [TrainingCalendarActivity]

    public var id: String { date }

    public init(date: String, planned: TrainingCalendarPlanned, state: State, status: String? = nil,
                credited: Bool = false, activities: [TrainingCalendarActivity] = []) {
        self.date = date; self.planned = planned; self.state = state; self.status = status
        self.credited = credited; self.activities = activities
    }
}

public nonisolated struct TrainingCalendarPlanned: Codable, Sendable, Equatable {
    public var name: String
    /// `strength` | `interval` | `z2` | `rest` | `optional` (the verdict vocabulary). Opaque
    /// beyond the letter + owed test, so B-88 template refs can arrive without breaking it.
    public var type: String
    public var sessionType: String?
    public var prescription: String?
    /// `snapshot` (what was planned that day) | `plan` | `table` | `device` (this phone's own
    /// snapshot store, C-4).
    public var source: String
    public var templateId: Int?

    public init(name: String, type: String, sessionType: String? = nil, prescription: String? = nil,
                source: String, templateId: Int? = nil) {
        self.name = name; self.type = type; self.sessionType = sessionType; self.prescription = prescription
        self.source = source; self.templateId = templateId
    }

    public static let owedTypes: Set<String> = ["strength", "interval", "z2"]
    public var isOwed: Bool { Self.owedTypes.contains(type) }

    /// The cell letter: S strength · I intervals · Z zone 2 · nil rest / not owed.
    public static func letter(forType type: String) -> String? {
        switch type {
        case "strength": "S"
        case "interval": "I"
        case "z2": "Z"
        default: nil
        }
    }
}

public nonisolated struct TrainingCalendarActivity: Codable, Sendable, Equatable {
    public var activityId: Int
    public var type: String?
    public var durationSec: Int?
    public var z2Share: Double?

    public init(activityId: Int, type: String?, durationSec: Int?, z2Share: Double? = nil) {
        self.activityId = activityId; self.type = type; self.durationSec = durationSec; self.z2Share = z2Share
    }
}

public nonisolated struct TrainingCalendarSummary: Codable, Sendable, Equatable {
    /// Q1: the credited count — partial days are counted apart, never credited.
    public var done: Int
    public var partial: Int
    public var missed: Int
    public var unknown: Int
    public var planned: Int
    public var rest: Int
    public var owedToDate: Int

    public init(done: Int, partial: Int, missed: Int, unknown: Int, planned: Int, rest: Int, owedToDate: Int) {
        self.done = done; self.partial = partial; self.missed = missed; self.unknown = unknown
        self.planned = planned; self.rest = rest; self.owedToDate = owedToDate
    }

    /// The hub's `summarize` over states (owed to date = done + partial + missed + unknown).
    public init(days: [TrainingCalendarDay]) {
        func n(_ s: TrainingCalendarDay.State) -> Int { days.filter { $0.state == s }.count }
        self.init(done: n(.done), partial: n(.partial), missed: n(.missed), unknown: n(.unknown),
                  planned: n(.planned), rest: n(.rest), owedToDate: n(.done) + n(.partial) + n(.missed) + n(.unknown))
    }
}

public extension TrainingCalendarMonth {
    /// The ISO dates (`yyyy-MM-dd`) of `month` (`yyyy-MM`) with their weekday (Mon = 0 … Sun = 6);
    /// nil for a malformed month. Pure civil-date math (UTC Gregorian; no clock, no zone).
    static func dates(of month: String) -> [(iso: String, weekday: Int)]? {
        let parts = month.split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!   // civil-date math only, never a "today"
        guard let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
              let range = cal.range(of: .day, in: .month, for: first) else { return nil }
        return range.map { day in
            let date = cal.date(from: DateComponents(year: y, month: m, day: day))!
            let wd = (cal.component(.weekday, from: date) + 5) % 7   // Sun = 1 → 6, Mon = 2 → 0
            return (String(format: "%04d-%02d-%02d", y, m, day), wd)
        }
    }

    /// A month built on the phone when the hub cannot answer (404 / offline, B-52) or for previews:
    /// `planned(iso, weekday)` names each day's session; with no completion knowledge every past
    /// owed day is `.unknown` (never missed), today/future owed days `.planned`, the rest `.rest`.
    static func offline(month: String, today: String,
                        planned: (_ iso: String, _ weekday: Int) -> TrainingCalendarPlanned) -> TrainingCalendarMonth? {
        guard let dates = dates(of: month) else { return nil }
        let days = dates.map { d -> TrainingCalendarDay in
            let p = planned(d.iso, d.weekday)
            let state: TrainingCalendarDay.State = !p.isOwed ? .rest : (d.iso >= today ? .planned : .unknown)
            return TrainingCalendarDay(date: d.iso, planned: p, state: state)
        }
        return TrainingCalendarMonth(month: month, today: today, syncedThrough: nil, days: days,
                                     summary: TrainingCalendarSummary(days: days))
    }
}

/// W-B92 C-3 — the Training Calendar's hub slice. `HubDataProvider` / `MockDataProvider` conform
/// in their own `+TrainingCalendar` files.
public protocol TrainingCalendarProviding: Sendable {
    /// `GET /api/v1/training/calendar?month=YYYY-MM`
    func trainingCalendar(month: String) async throws -> TrainingCalendarMonth
}

/// An older hub without the route (404): the phone builds the month offline instead.
public struct TrainingCalendarUnavailable: Error, Sendable, Equatable {
    public init() {}
}

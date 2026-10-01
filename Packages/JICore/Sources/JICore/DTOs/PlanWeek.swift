import Foundation

/// W-SSOT-1 SS-7: `GET /api/v1/planning/week?start=YYYY-MM-DD` — seven days of the hub's ONE
/// `app/planning/schedule.py::session_for` answer (latest plan, owed-session priority, table
/// fallback), the same call `morning_go` makes. The app prefers it over re-deriving the week from
/// `/planning/plan-sessions` rows (`PlanScheduleResolver`).
public struct PlanWeekOut: Codable, Sendable, Equatable {
    /// The Monday the week starts on (ISO date).
    public var start: String
    public var days: [PlanWeekDayOut]
    public init(start: String, days: [PlanWeekDayOut]) { self.start = start; self.days = days }
}

/// One day of the served week (HT golden `tests/fixtures/ssot1/planning_week.json`).
public struct PlanWeekDayOut: Codable, Sendable, Equatable {
    public var date: String
    /// Mon = 0 … Sun = 6.
    public var weekday: Int
    /// `plan.plan_session.session_id`; nil for a day without a plan session (rest / table fallback).
    public var sessionId: Int?
    /// The plan session's own name ("Interval Run") — the rows' vocabulary.
    public var name: String?
    /// `plan.plan_session.session_type` — "strength" | "cardio" | "rest".
    public var sessionType: String?
    /// The gate's session in the table vocabulary ("Norwegian 4x4 intervals") — what morning_go
    /// calls the day; the name the app shows and matches on.
    public var prescription: String?
    /// The gate type — "strength" | "interval" | "z2" | "rest" | "optional".
    public var type: String?
    /// Where the answer came from ("plan", or the table fallback).
    public var source: String?

    public init(date: String, weekday: Int, sessionId: Int? = nil, name: String? = nil, sessionType: String? = nil,
                prescription: String?, type: String?, source: String? = "plan") {
        self.date = date; self.weekday = weekday; self.sessionId = sessionId; self.name = name
        self.sessionType = sessionType; self.prescription = prescription; self.type = type; self.source = source
    }
}

public struct PlanWeekUnavailable: Error, Sendable, Equatable {
    public init() {}
}

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

public struct PlanWeekDayOut: Codable, Sendable, Equatable {
    public var date: String
    /// Mon = 0 … Sun = 6.
    public var weekday: Int
    /// The session's name in the table vocabulary ("Long Zone 2 75-90min"); nil = the hub has none.
    public var session: String?
    /// "strength" | "interval" | "z2" | "rest" | "optional"; nil when the hub sends none.
    public var sessionType: String?

    public init(date: String, weekday: Int, session: String?, sessionType: String?) {
        self.date = date; self.weekday = weekday; self.session = session; self.sessionType = sessionType
    }

    private enum CodingKeys: String, CodingKey { case date, weekday, session, sessionType, name, type }

    /// `session`/`session_type` are the contract; `name`/`type` are accepted too so a hub that
    /// spells the day like the plan-session rows still decodes (card fixed the route, not the keys).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        weekday = try c.decode(Int.self, forKey: .weekday)
        session = try c.decodeIfPresent(String.self, forKey: .session) ?? c.decodeIfPresent(String.self, forKey: .name)
        sessionType = try c.decodeIfPresent(String.self, forKey: .sessionType) ?? c.decodeIfPresent(String.self, forKey: .type)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(weekday, forKey: .weekday)
        try c.encodeIfPresent(session, forKey: .session)
        try c.encodeIfPresent(sessionType, forKey: .sessionType)
    }
}

public struct PlanWeekUnavailable: Error, Sendable, Equatable {
    public init() {}
}

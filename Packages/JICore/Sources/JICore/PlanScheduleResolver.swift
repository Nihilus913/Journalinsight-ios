import Foundation

/// W-FIX10 R-01: which session a day holds — ONE answer for Today, Training, the weekly plan and
/// the morning call. Since 2026-09-29 the hub's morning call follows `plan.plan_session.weekday`
/// (what the day sheet moves; `morning_go.py` `plan_weekdays_from_rows` / `session_for`), so the
/// app reads the same rows (`GET /planning/plan-sessions`, `TrainingProviding.planSessions()`).
/// The fixed weekday table (`JICompute.sessionByWeekday`) is only the fallback: before the
/// changeover date, and when the plan cannot be read. JICore does not depend on JICompute, so the
/// table comes in as `fixedWeek`.
public nonisolated enum ScheduledSessionKind: String, Sendable, Equatable {
    case strength, interval, z2, rest, optional
}

public nonisolated struct ScheduledSession: Sendable, Equatable {
    public let name: String
    public let kind: ScheduledSessionKind
    public init(name: String, kind: ScheduledSessionKind) { self.name = name; self.kind = kind }
}

public nonisolated struct PlanScheduleResolver: Sendable, Equatable {
    /// `PLAN_WEEKDAYS_EFFECTIVE` (morning_go.py): earlier dates keep the fixed table, so history is
    /// never re-typed.
    public static let effectiveDate = "2026-09-29"

    /// Mon = 0 … Sun = 6 from the plan rows; nil = no plan to follow (the fallback answers).
    public let week: [ScheduledSession]?
    private let fixedWeek: [ScheduledSession]
    /// W-SSOT-1 SS-7: the served `/planning/week` answers by date (empty when not served).
    private let byDate: [String: ScheduledSession]

    public init(planSessions: [PlanSessionOut]?, fixedWeek: [ScheduledSession]) {
        self.init(planWeek: nil, planSessions: planSessions, fixedWeek: fixedWeek)
    }

    /// W-SSOT-1 SS-7: a served, complete `/planning/week` (seven days, Mon…Sun) wins — it IS the
    /// hub's `session_for`; otherwise the week is re-derived from the plan-session rows as before.
    public init(planWeek: PlanWeekOut?, planSessions: [PlanSessionOut]?, fixedWeek: [ScheduledSession]) {
        self.fixedWeek = fixedWeek
        if let served = Self.served(planWeek, fixedWeek: fixedWeek) {
            self.week = served.week
            self.byDate = served.byDate
        } else {
            self.week = Self.weekdays(from: planSessions ?? [], fixedWeek: fixedWeek)
            self.byDate = [:]
        }
    }

    /// `session_for(day, plan)`: the served week's answer for that date; else the plan's session
    /// from the changeover date on, else `fallback` (the caller's `JICompute.sessionFor(iso)`,
    /// which keeps the Saturday changeover).
    public func session(on iso: String, weekday: Int, fallback: ScheduledSession) -> ScheduledSession {
        if let hub = byDate[iso] { return hub }
        guard let week, iso >= Self.effectiveDate, week.indices.contains(weekday) else { return fallback }
        return week[weekday]
    }

    /// The served `/planning/week` answer for `iso`; nil when no week was served or it does not
    /// cover that date.
    public func servedSession(on iso: String) -> ScheduledSession? { byDate[iso] }

    /// The served week as Mon…Sun sessions; nil unless every weekday 0…6 is present exactly once.
    static func served(_ w: PlanWeekOut?, fixedWeek: [ScheduledSession])
        -> (week: [ScheduledSession], byDate: [String: ScheduledSession])? {
        guard let days = w?.days, days.count == 7, Set(days.map(\.weekday)) == Set(0...6) else { return nil }
        var week = [ScheduledSession](repeating: canonical(.rest, fixedWeek: fixedWeek), count: 7)
        var byDate: [String: ScheduledSession] = [:]
        for d in days {
            let s = session(for: d, fixedWeek: fixedWeek)
            week[d.weekday] = s
            byDate[d.date] = s
        }
        return (week, byDate)
    }

    /// One served day: the hub's `prescription` (table vocabulary) and gate `type` as sent. A day
    /// without them is mapped like a plan-session row (`name` + `session_type`), and no session at
    /// all is rest.
    static func session(for d: PlanWeekDayOut, fixedWeek: [ScheduledSession]) -> ScheduledSession {
        if let rx = d.prescription, !rx.trimmingCharacters(in: .whitespaces).isEmpty {
            let kind = d.type.flatMap(ScheduledSessionKind.init(rawValue:))
                ?? fixedWeek.first { $0.name == rx }?.kind
                ?? (rx.lowercased().contains("interval") ? .interval : .z2)
            return ScheduledSession(name: rx, kind: kind)
        }
        guard let name = d.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return canonical(.rest, fixedWeek: fixedWeek)
        }
        return session(for: PlanSessionOut(id: d.sessionId ?? -1, name: name, weekday: d.weekday, sessionType: d.sessionType),
                       fixedWeek: fixedWeek)
    }

    /// A session's kind by its name (the plan's week first, then the fixed table); nil = unknown.
    public func kind(named name: String) -> ScheduledSessionKind? {
        ((week ?? []) + fixedWeek).first { $0.name == name }?.kind
    }

    private static let owedOrder: [ScheduledSessionKind: Int] = [.strength: 0, .interval: 1, .z2: 2, .rest: 3]

    /// `plan_weekdays_from_rows`: two sessions on one day → the owed one wins; an empty day is rest.
    static func weekdays(from rows: [PlanSessionOut], fixedWeek: [ScheduledSession]) -> [ScheduledSession]? {
        guard !rows.isEmpty else { return nil }
        var byDay: [Int: ScheduledSession] = [:]
        for row in rows {
            guard let wd = row.weekday, (0...6).contains(wd) else { continue }
            let cand = session(for: row, fixedWeek: fixedWeek)
            if let cur = byDay[wd], (owedOrder[cand.kind] ?? 9) >= (owedOrder[cur.kind] ?? 9) { continue }
            byDay[wd] = cand
        }
        let rest = canonical(.rest, fixedWeek: fixedWeek)
        return (0..<7).map { byDay[$0] ?? rest }
    }

    /// `_plan_session`: one plan row in the table's vocabulary ("Day 2 Full Upper" → "Day 2 Full
    /// Upper + Z2 60min"; any interval row → the table's interval, other cardio → its long Z2).
    static func session(for row: PlanSessionOut, fixedWeek: [ScheduledSession]) -> ScheduledSession {
        let strengthMatch = fixedWeek.first { $0.kind == .strength && $0.name.hasPrefix(row.name) }
        switch row.sessionType {
        case "strength": return strengthMatch ?? ScheduledSession(name: row.name, kind: .strength)
        case "rest": return canonical(.rest, fixedWeek: fixedWeek)
        case nil where strengthMatch != nil: return strengthMatch!
        default:
            return canonical(row.name.lowercased().contains("interval") ? .interval : .z2, fixedWeek: fixedWeek)
        }
    }

    private static func canonical(_ kind: ScheduledSessionKind, fixedWeek: [ScheduledSession]) -> ScheduledSession {
        fixedWeek.first { $0.kind == kind } ?? ScheduledSession(name: kind == .rest ? "Rest" : kind.rawValue, kind: kind)
    }
}

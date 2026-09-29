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

    public init(planSessions: [PlanSessionOut]?, fixedWeek: [ScheduledSession]) {
        self.fixedWeek = fixedWeek
        self.week = Self.weekdays(from: planSessions ?? [], fixedWeek: fixedWeek)
    }

    /// `session_for(day, plan)`: the plan's session from the changeover date on, else `fallback`
    /// (the caller's `JICompute.sessionFor(iso)`, which keeps the Saturday changeover).
    public func session(on iso: String, weekday: Int, fallback: ScheduledSession) -> ScheduledSession {
        guard let week, iso >= Self.effectiveDate, week.indices.contains(weekday) else { return fallback }
        return week[weekday]
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

import Foundation
import SwiftUI
import JICore
import JICompute

/// B-57 W5 (board 3/01 "This week", 3/02 TrainingWeek): one Mon–Sun week built from what the phone
/// already caches — the plan-session weekdays (B-45/B-52, including a still-queued offline
/// assignment) and the gate's daily rows. S = an assigned strength session; I / R = the gate's
/// fixed interval / long-Z2 days (not user-assignable until B-40 templates); – = rest.
/// "Done" reuses the Training strip's 300-kcal proxy (`trainingDayStatus`) — no workout log exists
/// yet (B-38), so a day with no row is unknown (nil), never "missed".
public nonisolated enum TrainingWeekDayKind: String, Sendable, Equatable {
    case strength = "S", interval = "I", longRun = "R", rest = "–"
    /// W-FIX-P3 RG-66: the letter drawn — the SAME as the Month grid's (`TrainingCalendarPlanned.letter`):
    /// the long Zone 2 day is "Z" in Week and Month. (`rawValue` stays the gate's session type key.)
    public var letter: String { self == .longRun ? "Z" : rawValue }
    public var word: String {
        switch self {
        case .strength: "strength"
        case .interval: "intervals"
        case .longRun: "long run"
        case .rest: "rest"
        }
    }
}

public nonisolated let trainingWeekdayShortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

public nonisolated struct TrainingWeekDay: Sendable, Equatable, Identifiable {
    /// Mon = 0 … Sun = 6.
    public let weekday: Int
    public let date: String
    public let kind: TrainingWeekDayKind
    public let sessionName: String?
    public let sessionId: Int?
    /// true = trained, false = a past strength day below the floor, nil = unknown / not yet.
    public let done: Bool?
    public let isToday: Bool
    /// W-B40 fixer (B40-V2): the B-40 library workouts on this day that are not a plan session
    /// (the day sheet lists them too) — the strip marks them so strip and sheet agree.
    public var extras: [String] = []
    public var id: Int { weekday }
}

public nonisolated struct TrainingWeekSummary: Sendable, Equatable {
    public let days: [TrainingWeekDay]
    public let planTotal: Int
    public let assigned: Int
    /// nil = no gate row this week yet (unknown, never a zero).
    public let planDone: Int?
    public let next: TrainingWeekDay?

    public init(days: [TrainingWeekDay], planTotal: Int, assigned: Int, planDone: Int?, next: TrainingWeekDay?) {
        self.days = days; self.planTotal = planTotal; self.assigned = assigned; self.planDone = planDone; self.next = next
    }

    public var matchesPlan: Bool { planTotal > 0 && assigned == planTotal }

    /// W-FIX11 H1-14: the week's count is the strip's — every session day placed this week
    /// (strength, intervals, long run), not the plan's strength total (which can be unreachable when
    /// a session has no day), and a done day of any kind counts.
    public var weekSessionDays: Int { days.filter { $0.kind != .rest }.count }
    public var weekTotal: Int { weekSessionDays > 0 ? weekSessionDays : planTotal }
    /// nil = unknown (no gate row this week and nothing marked done) — never a zero.
    public var weekDone: Int? {
        let done = days.filter { $0.kind != .rest && $0.done == true }.count
        return planDone == nil && done == 0 ? nil : done
    }
    public var weekCountText: String { "\(weekDone.map(String.init) ?? "—") of \(weekTotal)" }

    public var doneText: String {
        guard planTotal > 0 else { return "No plan yet" }
        return "\(weekCountText) done"
    }

    public var nextSessionLabel: String? {
        guard let next, let name = next.sessionName else { return nil }
        return "\(trainingWeekdayShortNames[next.weekday]) · \(name)"
    }
}

nonisolated struct WeekSpineEntry: Equatable {
    let id: Int?; let name: String; let weekday: Int?; var kind: TrainingWeekDayKind = .strength
    /// PL-8: the workout template this plan session IS (hub `linked_refs`, migration 060); nil = unlinked.
    var templateId: Int? = nil
}

/// PL-8: the spine with each session's template link (session id → template id) — by id only.
nonisolated func plannerLinkingSpine(_ spine: [WeekSpineEntry], links: [Int: Int]) -> [WeekSpineEntry] {
    guard !links.isEmpty else { return spine }
    return spine.map { e in
        var e = e
        if let id = e.id, let tid = links[id] { e.templateId = tid }
        return e
    }
}

/// W-B40 fixer (B40-V1): what a plan session is, from the hub's `session_type`. Cardio splits into
/// intervals and long runs by name — the plan table has no finer type.
nonisolated func trainingSessionKind(type: String?, name: String) -> TrainingWeekDayKind {
    switch type?.lowercased() {
    case "rest": return .rest
    case "cardio":
        let key = name.lowercased()
        return key.contains("interval") || key.contains("4x4") || key.contains("4×4") ? .interval : .longRun
    default: return .strength
    }
}

/// The strength spine plus the plan's cardio / rest sessions the hub lists
/// (`GET /planning/plan-sessions`) — the ones no exercise row carries. Each id once.
nonisolated func trainingDaySpine(strength: [WeekSpineEntry], sessions: [PlanSessionOut]) -> [WeekSpineEntry] {
    let known = Set(strength.compactMap(\.id))
    return strength + sessions.compactMap { s in
        let kind = trainingSessionKind(type: s.sessionType, name: s.name)
        guard kind != .strength, !known.contains(s.id) else { return nil }
        return WeekSpineEntry(id: s.id, name: s.name, weekday: s.weekday, kind: kind)
    }
}

/// The cached plan-session spine first (it holds the offline-queued weekday), then any session
/// only the exercise rows know about. One entry per session name.
nonisolated func weekSpine(planSessions: [PlanSessionOut], exercises: [Exercise]) -> [WeekSpineEntry] {
    var seen = Set<String>()
    var out: [WeekSpineEntry] = []
    for s in planSessions where !seen.contains(s.name) {
        seen.insert(s.name); out.append(WeekSpineEntry(id: s.id, name: s.name, weekday: s.weekday))
    }
    for name in orderedSessionNames(exercises) where !seen.contains(name) {
        seen.insert(name)
        let r = weekStripSession(named: name, exercises: exercises, planSessions: planSessions)
        out.append(WeekSpineEntry(id: r.id, name: name, weekday: r.weekday))
    }
    return out
}

/// `otherSessions` (W-B40 fixer): the hub's full plan-session list. When it holds the plan's
/// cardio sessions, I / R follow THEIR weekdays (what the day sheet changes); without it (an older
/// hub, nothing cached yet) they follow the morning-call schedule as before. `templates`: the
/// B-40 library, whose workouts on a day are that day's `extras`.
/// W-FIX10 R-01: `schedule` is the plan the fallback days are resolved from (`scheduledSession`);
/// nil = `otherSessions`.
public nonisolated func trainingWeekSummary(
    planSessions: [PlanSessionOut], exercises: [Exercise], daily: [DailyKpiRow], today: String,
    otherSessions: [PlanSessionOut] = [], templates: [WorkoutTemplate] = [], schedule: [PlanSessionOut]? = nil,
    links: [Int: Int] = [:]
) -> TrainingWeekSummary {
    let spine = plannerLinkingSpine(weekSpine(planSessions: planSessions, exercises: exercises), links: links)
    let others = plannerLinkingSpine(trainingDaySpine(strength: [], sessions: otherSessions), links: links)
    let templateNames = Dictionary(templates.map { ($0.templateId, $0.name) }, uniquingKeysWith: { a, _ in a })
    let linkSpine = spine + others
    let assigned = spine.filter { $0.weekday.map { (0...6).contains($0) } ?? false }.count
    guard let todayWd = try? CalendarMath.isoWeekday(today), let monday = try? CalendarMath.addDays(today, -todayWd) else {
        return TrainingWeekSummary(days: [], planTotal: spine.count, assigned: assigned, planDone: nil, next: nil)
    }
    let byDate = Dictionary(daily.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    var days: [TrainingWeekDay] = []
    for wd in 0..<7 {
        let date = (try? CalendarMath.addDays(monday, wd)) ?? monday
        let strength = spine.filter { $0.weekday == wd }
        var kind = TrainingWeekDayKind.rest
        var name: String?
        if !strength.isEmpty {
            kind = .strength
            name = strength.map(\.name).joined(separator: " + ")
        } else if !others.isEmpty {
            if let c = others.first(where: { $0.weekday == wd && ($0.kind == .interval || $0.kind == .longRun) }) {
                kind = c.kind; name = c.templateId.flatMap { templateNames[$0] } ?? c.name   // PL-8: a linked session is its template
            }
        } else if let planned = scheduledSession(on: date, planSessions: schedule ?? otherSessions) {
            if planned.type == .interval { kind = .interval; name = planned.name }
            else if planned.type == .z2 { kind = .longRun; name = planned.name }
        }
        var done: Bool?
        if kind == .strength, date <= today, let row = byDate[date] {
            switch trainingDayStatus(kcalBurnedActive: row.values["kcal_burned_active"] ?? nil, isFuture: false) {
            case .good: done = true
            case .miss: done = date == today ? nil : false
            case .neutral, .future: done = nil
            }
        }
        // PL-8: a template linked (by id) to a session on THIS day is that session — not an extra.
        let linkedHere = Set(linkSpine.filter { $0.weekday == wd }.compactMap(\.templateId))
        let extras = templates.filter { $0.weekdays.contains(wd) && !linkedHere.contains($0.templateId) }.map(\.name)
        days.append(TrainingWeekDay(weekday: wd, date: date, kind: kind, sessionName: name,
                                    sessionId: strength.first?.id, done: done, isToday: date == today, extras: extras))
    }
    let hasWeekRows = daily.contains { $0.date >= monday && $0.date <= today }
    let doneCount = days.filter { $0.done == true }.count
    let planDone = hasWeekRows ? min(doneCount, spine.count) : nil
    let next = days.first { $0.kind == .strength && $0.date >= today && $0.done != true }
    return TrainingWeekSummary(days: days, planTotal: spine.count, assigned: assigned, planDone: planDone, next: next)
}

public extension EnvironmentValues {
    /// B-57 W5: this week's plan for Day, Goals and Decide (set by the App; nil = unknown → "—").
    @Entry var trainingWeekSummary: TrainingWeekSummary?
}

// MARK: - W-FIX10 R-01: the one day → session answer

/// The fixed weekday table (`JICompute.sessionByWeekday`) in the resolver's vocabulary — the
/// fallback only.
public nonisolated let fixedScheduleWeek: [ScheduledSession] = sessionByWeekday.map {
    ScheduledSession(name: $0.name, kind: ScheduledSessionKind(rawValue: $0.type.rawValue) ?? .optional)
}

/// The resolver for a plan-session list (`GET /planning/plan-sessions`); empty / nil = no plan.
public nonisolated func planSchedule(_ planSessions: [PlanSessionOut]?, week: PlanWeekOut? = nil) -> PlanScheduleResolver {
    PlanScheduleResolver(planWeek: week, planSessions: planSessions, fixedWeek: fixedScheduleWeek)
}

/// The plan's week as the gate's `PlannedSession`s (Mon = 0 … Sun = 6); nil = no plan to follow.
public nonisolated func plannedWeek(_ resolver: PlanScheduleResolver) -> [GateSession]? {
    resolver.week?.map { GateSession(name: $0.name, type: SessionType(rawValue: $0.kind.rawValue)) }
}

/// The session planned for an ISO date: the plan's weekday from the changeover date on (what the
/// hub's morning call follows), else the fixed table (`JICompute.sessionFor`). nil = bad date.
/// W-SSOT-1 SS-7: a served `/planning/week` covering `iso` answers first (the hub's `session_for`).
public nonisolated func scheduledSession(on iso: String, planSessions: [PlanSessionOut]?, week: PlanWeekOut? = nil) -> GateSession? {
    let resolver = planSchedule(planSessions, week: week)
    if let hub = resolver.servedSession(on: iso) { return GateSession(name: hub.name, type: SessionType(rawValue: hub.kind.rawValue)) }
    return try? JICompute.sessionFor(iso, plan: plannedWeek(resolver))
}

/// W-SSOT-1 SS-7: the Monday (ISO date) of `iso`'s week — the `start` `/planning/week` takes.
/// Pure calendar arithmetic via `DayKey` (no `Calendar.current`); nil for a malformed date.
public nonisolated func planWeekStart(_ iso: String) -> String? {
    DayKey(iso: iso)?.mondayOfWeek.iso
}

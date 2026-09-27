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

    public var doneText: String {
        guard planTotal > 0 else { return "No plan yet" }
        return "\(planDone.map(String.init) ?? "—") of \(planTotal) done"
    }

    public var nextSessionLabel: String? {
        guard let next, let name = next.sessionName else { return nil }
        return "\(trainingWeekdayShortNames[next.weekday]) · \(name)"
    }
}

nonisolated struct WeekSpineEntry: Equatable { let id: Int?; let name: String; let weekday: Int? }

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

public nonisolated func trainingWeekSummary(
    planSessions: [PlanSessionOut], exercises: [Exercise], daily: [DailyKpiRow], today: String
) -> TrainingWeekSummary {
    let spine = weekSpine(planSessions: planSessions, exercises: exercises)
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
        } else if let planned = try? JICompute.sessionFor(date) {
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
        days.append(TrainingWeekDay(weekday: wd, date: date, kind: kind, sessionName: name,
                                    sessionId: strength.first?.id, done: done, isToday: date == today))
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

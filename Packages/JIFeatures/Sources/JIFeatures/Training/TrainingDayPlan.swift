import Foundation
import JICore

// W-B40 L3 (B-82) — Training day-first. Tap a day → a preview of THAT day's session(s) → change =
// pick from the plan sessions and the B-40 workout library. The pure half: what a day shows, what
// the picker offers, and which writes one pick turns into. Two existing day links, no new model:
//   • a plan session's weekday — `PUT /planning/plan-sessions/{id}` (B-45), Outbox `plan_weekday` (B-52);
//   • a library workout's `weekdays` — the B-40 template↔day link, written with the library's own
//     queued template write (Outbox `workout_template`, W-B40 L2).
// A pick replaces ONE entry of the day (or adds one): a strength + run day keeps its other half.

/// What the user picked for a day.
public nonisolated enum TrainingDayChoice: Sendable, Equatable {
    case planSession(id: Int, name: String)
    case template(WorkoutTemplate)
}

/// One write a pick turns into.
public nonisolated enum TrainingDayWrite: Sendable, Equatable {
    /// `PUT /planning/plan-sessions/{id}` — nil takes the session off every day (it stays in the plan).
    case sessionWeekday(id: Int, name: String, weekday: Int?)
    /// The template's full new `weekdays` (sorted, distinct).
    case templateWeekdays(WorkoutTemplate, [Int])
}

/// A day's preview: its entries in plan order (strength, then the plan's cardio / rest sessions —
/// or, while the hub hasn't listed those, the morning-call schedule's fixed interval / long run —
/// then library workouts). Empty = rest.
public nonisolated struct TrainingDayPreview: Sendable, Equatable {
    public enum Entry: Sendable, Equatable, Identifiable {
        /// A plan session (nil id = the hub never told us its `plan_session` id: shown, not changeable).
        case strength(id: Int?, name: String, lifts: [Exercise])
        case template(WorkoutTemplate)
        /// A cardio / rest plan session the hub lists (W-B40 fixer, B40-V1): changeable like a
        /// strength session, through its `plan_session` weekday.
        case session(id: Int, name: String, kind: TrainingWeekDayKind)
        /// The schedule's session for the day (`scheduledSession`: the plan's weekdays, the fixed
        /// gate table only as fallback — W-FIX10 R-01) — not assignable, never removed here.
        case scheduled(name: String, kind: TrainingWeekDayKind)

        public var id: String {
            switch self {
            case .strength(let id, let name, _): "s\(id.map(String.init) ?? name)"
            case .template(let t): "t\(t.templateId)"
            case .session(let id, _, _): "s\(id)"
            case .scheduled(let name, _): "c\(name)"
            }
        }

        public var title: String {
            switch self {
            case .strength(_, let name, _): name
            case .template(let t): t.name
            case .session(_, let name, _): name
            case .scheduled(let name, _): name
            }
        }

        /// The pick that stands for this entry (nil = not changeable from the app).
        public var choice: TrainingDayChoice? {
            switch self {
            case .strength(let id?, let name, _): .planSession(id: id, name: name)
            case .template(let t): .template(t)
            case .session(let id, let name, _): .planSession(id: id, name: name)
            case .strength(nil, _, _), .scheduled: nil
            }
        }
    }

    public let weekday: Int
    public let date: String
    public let isToday: Bool
    public let entries: [Entry]
    public var isRest: Bool { entries.isEmpty }
}

/// One row of the picker.
public nonisolated struct TrainingDayOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let choice: TrainingDayChoice
    /// Mon = 0 … Sun = 6 — the days it is on now (drives "On Mon, Fri" / "Not on a day").
    public let currentDays: [Int]
    public let isOnThisDay: Bool
    /// What it is (a library row: `.strength` = no plan kind; the glyph comes from the template).
    public let kind: TrainingWeekDayKind
    /// The library row it came from (nil for a plan session).
    public let template: WorkoutTemplate?
}

public nonisolated struct TrainingDayOptions: Sendable, Equatable {
    /// Plan sessions with no library workout of the same name.
    public let plan: [TrainingDayOption]
    /// The whole workout library, in library order.
    public let library: [TrainingDayOption]
}

/// Names compare case- and whitespace-insensitively ("day 1  full upper" = "Day 1 Full Upper").
nonisolated func trainingNameKey(_ s: String) -> String {
    s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// The plan session a library workout stands for, when it carries that session's name — so the
/// same session is never offered twice and its day stays ONE link (the plan session's).
nonisolated func linkedSession(_ t: WorkoutTemplate, spine: [WeekSpineEntry]) -> WeekSpineEntry? {
    let key = trainingNameKey(t.name)
    return spine.first { $0.id != nil && trainingNameKey($0.name) == key }
}

nonisolated func trainingDayPreview(
    day: TrainingWeekDay, spine: [WeekSpineEntry], exercises: [Exercise], templates: [WorkoutTemplate]
) -> TrainingDayPreview {
    let wd = day.weekday
    var entries: [TrainingDayPreview.Entry] = spine.filter { $0.weekday == wd }.map { s in
        if s.kind != .strength, let id = s.id { return .session(id: id, name: s.name, kind: s.kind) }
        return .strength(id: s.id, name: s.name, lifts: exercises.filter { $0.sessionName == s.name })
    }
    for t in templates where t.weekdays.contains(wd) && linkedSession(t, spine: spine) == nil {
        entries.append(.template(t))
    }
    // B40-V1: the schedule stands in only while the hub hasn't listed the plan's own cardio
    // sessions for this day — and a library workout added to the day never hides it.
    let hasPlanCardio = entries.contains { if case .session = $0 { true } else { false } }
    if !hasPlanCardio, day.kind == .interval || day.kind == .longRun {
        let at = entries.firstIndex { if case .template = $0 { true } else { false } } ?? entries.endIndex
        entries.insert(.scheduled(name: day.sessionName ?? (day.kind.word.prefix(1).uppercased() + day.kind.word.dropFirst()), kind: day.kind), at: at)
    }
    return TrainingDayPreview(weekday: wd, date: day.date, isToday: day.isToday, entries: entries)
}

nonisolated func trainingDayOptions(weekday wd: Int, spine: [WeekSpineEntry], templates: [WorkoutTemplate]) -> TrainingDayOptions {
    var linkedIds = Set<Int>()
    let library: [TrainingDayOption] = templates.map { t in
        if let s = linkedSession(t, spine: spine), let id = s.id {
            linkedIds.insert(id)
            let days = s.weekday.map { [$0] } ?? []
            return TrainingDayOption(id: "t\(t.templateId)", title: s.name, choice: .planSession(id: id, name: s.name),
                                     currentDays: days, isOnThisDay: days.contains(wd), kind: s.kind, template: t)
        }
        let days = Array(Set(t.weekdays)).sorted()
        return TrainingDayOption(id: "t\(t.templateId)", title: t.name, choice: .template(t),
                                 currentDays: days, isOnThisDay: days.contains(wd), kind: .strength, template: t)
    }
    let plan: [TrainingDayOption] = spine.compactMap { s in
        guard let id = s.id, !linkedIds.contains(id) else { return nil }
        let days = s.weekday.map { [$0] } ?? []
        return TrainingDayOption(id: "s\(id)", title: s.name, choice: .planSession(id: id, name: s.name),
                                 currentDays: days, isOnThisDay: days.contains(wd), kind: s.kind, template: nil)
    }
    return TrainingDayOptions(plan: plan, library: library)
}

/// The writes one pick makes: take `removing` off the day (if it is ours to change), put `adding`
/// on it (if it is not already there). Picking what is already there writes nothing. A template's
/// days are read from `templates` (the library's current rows), never from a possibly stale choice.
nonisolated func trainingDayWrites(
    weekday wd: Int, adding: TrainingDayChoice?, removing: TrainingDayPreview.Entry?,
    spine: [WeekSpineEntry], templates: [WorkoutTemplate]
) -> [TrainingDayWrite] {
    func current(_ t: WorkoutTemplate) -> WorkoutTemplate { templates.first { $0.templateId == t.templateId } ?? t }
    let removeChoice = removing?.choice
    if let adding, let removeChoice, trainingSameChoice(adding, removeChoice) { return [] }
    var writes: [TrainingDayWrite] = []
    switch removeChoice {
    case .planSession(let id, let name)?:
        if spine.first(where: { $0.id == id })?.weekday == wd { writes.append(.sessionWeekday(id: id, name: name, weekday: nil)) }
    case .template(let t)?:
        let t = current(t)
        if t.weekdays.contains(wd) { writes.append(.templateWeekdays(t, Array(Set(t.weekdays).subtracting([wd])).sorted())) }
    case nil: break
    }
    switch adding {
    case .planSession(let id, let name)?:
        if spine.first(where: { $0.id == id })?.weekday != wd { writes.append(.sessionWeekday(id: id, name: name, weekday: wd)) }
    case .template(let t)?:
        let t = current(t)
        if !t.weekdays.contains(wd) { writes.append(.templateWeekdays(t, Array(Set(t.weekdays).union([wd])).sorted())) }
    case nil: break
    }
    return writes
}

/// Same session / same library row — by id: an entry may carry an older copy of the same row.
nonisolated func trainingSameChoice(_ a: TrainingDayChoice, _ b: TrainingDayChoice) -> Bool {
    switch (a, b) {
    case (.planSession(let x, _), .planSession(let y, _)): x == y
    case (.template(let x), .template(let y)): x.templateId == y.templateId
    default: false
    }
}

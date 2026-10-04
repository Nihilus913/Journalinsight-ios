import Foundation
import JICore

// W-PLANNER — the Planner's pure half: the one list of every workout (assigned or not), its
// filters, and what a drag onto a day writes. No new model: a row is a plan session (its day =
// `plan_session.weekday`) or a library template (its days = `weekdays`), the same two links the
// day sheet already changes (`TrainingDayWrite`).

/// PL-3: the rows the Planner lists — the hub's `/planning/workouts` (or, for an older hub, the
/// same list built from the cached rows), with this phone's own day changes laid over it:
/// a session's day from the spine (which holds an offline-queued weekday), a template's days,
/// name and Garmin link from the library (which holds a queued template write). A template made
/// on this phone that the hub has not listed yet is appended; one the loaded library no longer
/// has is dropped.
nonisolated func plannerWorkoutRows(
    hub: [PlannerWorkout]?, exercises: [Exercise], planSessions: [PlanSessionOut], spine: [WeekSpineEntry],
    templates: [WorkoutTemplate], libraryLoaded: Bool
) -> [PlannerWorkout] {
    let base = hub ?? plannerWorkoutsFallback(exercises: exercises, planSessions: planSessions, templates: templates)
    let byTemplate = Dictionary(templates.map { ($0.templateId, $0) }, uniquingKeysWith: { a, _ in a })
    var listed = Set<Int>()
    var out: [PlannerWorkout] = []
    for var row in base {
        if let sid = row.sessionId, let s = spine.first(where: { $0.id == sid }) {
            row.weekdays = s.weekday.map { [$0] } ?? []
        } else if let tid = row.templateId {
            listed.insert(tid)
            if let t = byTemplate[tid] {
                row.weekdays = Array(Set(t.weekdays)).sorted()
                row.name = t.name
                if let g = t.garmin { row.garmin = g; row.onGarmin = true }
            } else if libraryLoaded && !templates.isEmpty {
                continue
            }
        }
        out.append(row)
    }
    for t in templates where !listed.contains(t.templateId) && hub != nil {
        out.append(PlannerWorkout(ref: "t\(t.templateId)", kind: .template, name: t.name, sport: t.hasStrength ? "strength" : t.activity,
                                  weekdays: Array(Set(t.weekdays)).sorted(), garmin: t.garmin, editable: true))
    }
    return out
}

// MARK: - PL-4: the screen's words and filters

/// The Planner's one statement (report §5: one statement per screen).
public nonisolated let plannerStatement = "Your week, and every workout you can put in it."

/// Toby 2026-10-04 answer 1: All / Strength / Run / Not on a day. "Strength + Run" is a property of
/// a day, never of one stored workout — it is gone.
public nonisolated enum PlannerFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All", strength = "Strength", run = "Run", unassigned = "Not on a day"
    public var id: String { rawValue }
}

/// Strength = a strength session, or a template with a strength segment; Run = everything else;
/// Not on a day = no weekday at all.
nonisolated func plannerIsStrength(_ row: PlannerWorkout, templates: [WorkoutTemplate]) -> Bool {
    if row.isStrength { return true }
    guard let tid = row.templateId else { return false }
    return templates.first { $0.templateId == tid }?.hasStrength ?? false
}

nonisolated func plannerFiltered(_ rows: [PlannerWorkout], _ filter: PlannerFilter, templates: [WorkoutTemplate]) -> [PlannerWorkout] {
    switch filter {
    case .all: rows
    case .strength: rows.filter { plannerIsStrength($0, templates: templates) }
    case .run: rows.filter { !plannerIsStrength($0, templates: templates) }
    case .unassigned: rows.filter { $0.weekdays.isEmpty }
    }
}

/// What an empty filter says — specific to the filter, never a bare "None in this filter."
nonisolated func plannerEmptyText(_ filter: PlannerFilter, hasAny: Bool) -> String {
    guard hasAny else { return "No workouts yet — tap + or import from Garmin Connect." }
    switch filter {
    case .all: return "No workouts yet — tap + or import from Garmin Connect."
    case .strength: return "No strength workouts in your plan or library."
    case .run: return "No runs in your plan or library."
    case .unassigned: return "Every workout is on a day."
    }
}

/// "Mon, Fri" / "Not on a day".
nonisolated func plannerDaysText(_ days: [Int]) -> String {
    let names = days.filter { (0...6).contains($0) }.map { trainingWeekdayShortNames[$0] }
    return names.isEmpty ? "Not on a day" : names.joined(separator: ", ")
}

/// "6 lifts · Mon" · "40 min Z2 · Mon" · "Cardio · Tue".
nonisolated func plannerRowSubtitle(_ row: PlannerWorkout, template: WorkoutTemplate?) -> String {
    let what: String
    if let template {
        what = WorkoutFormat.summary(template)
    } else if row.kind == .planSession && row.isStrength {
        what = row.liftCount > 0 ? "\(row.liftCount) lift\(row.liftCount == 1 ? "" : "s")" : (row.summary ?? "Strength")
    } else {
        what = row.summary ?? (row.kind == .planSession ? "Cardio · in your plan" : "Workout")
    }
    return what + " · " + plannerDaysText(row.weekdays)
}

nonisolated func plannerRowSymbol(_ row: PlannerWorkout, template: WorkoutTemplate?) -> String {
    if let t = template { return WorkoutFormat.sportSymbol(t.hasStrength ? .strength : (t.effectiveSegments.first?.sport ?? .running)) }
    return row.isStrength ? "dumbbell.fill" : "figure.run"
}

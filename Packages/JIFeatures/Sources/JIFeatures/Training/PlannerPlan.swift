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

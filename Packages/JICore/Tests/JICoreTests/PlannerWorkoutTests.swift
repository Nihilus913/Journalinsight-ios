import Foundation
import Testing
@testable import JICore

// W-PLANNER PL-3: `GET /api/v1/planning/workouts` (HT PL-1) — the active plan's sessions ∪ the
// workout templates as ONE list. Fixture: Resources/planner/planning_workouts.json, written to the
// PL-1 shape in the Wave Card (7 sessions, Rest excluded, + 4 templates; Day 4 unassigned).

private func plannerFixture() throws -> [PlannerWorkout] {
    let url = try #require(Bundle.module.url(forResource: "planning_workouts", withExtension: "json", subdirectory: "Resources/planner"))
    return try JSON.decoder.decode([PlannerWorkout].self, from: Data(contentsOf: url))
}

/// The cached rows an old hub (no `/planning/workouts`) leaves the phone with: the strength
/// exercise rows, the whole plan-session list (cardio + rest), the template library.
private func cachedExercises() -> [Exercise] {
    let days: [(Int, String, Int?)] = [(1, "Day 1 Full Upper", 0), (2, "Day 2 Full Upper", 2), (3, "Day 3 Full Upper", 4), (4, "Day 4 Full Upper", nil)]
    return days.flatMap { sid, name, wd in
        (0..<6).map { i in
            Exercise(exerciseId: sid * 10 + i, sessionName: name, exerciseName: "Lift \(i)", sets: 3, repsTarget: "8",
                     currentWeightKg: 20, progressionStepKg: 2.5, weekday: wd, sessionId: sid)
        }
    }
}

private let cachedPlanSessions: [PlanSessionOut] = [
    PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 0, sessionType: "strength"),
    PlanSessionOut(id: 2, name: "Day 2 Full Upper", weekday: 2, sessionType: "strength"),
    PlanSessionOut(id: 3, name: "Day 3 Full Upper", weekday: 4, sessionType: "strength"),
    PlanSessionOut(id: 4, name: "Day 4 Full Upper", weekday: nil, sessionType: "strength"),
    PlanSessionOut(id: 5, name: "Interval Run", weekday: 1, sessionType: "cardio"),
    PlanSessionOut(id: 6, name: "Long Zone 2", weekday: 3, sessionType: "cardio"),
    PlanSessionOut(id: 7, name: "Rest", weekday: 6, sessionType: "rest"),
    PlanSessionOut(id: 8, name: "Interval Run 2", weekday: 5, sessionType: "cardio"),
]

private func template(_ id: Int, _ name: String, _ days: [Int]) -> WorkoutTemplate {
    WorkoutTemplate(templateId: id, name: name, activity: "running", location: .outdoor, weekdays: days,
                    steps: [WorkoutStep(purpose: .work, seconds: 2400, hrLo: 120, hrHi: 140)], updatedAt: "2026-10-01T00:00:00Z")
}

private let cachedTemplates: [WorkoutTemplate] = [
    template(1, "Long Run Zone 2", [6]), template(2, "Zone 2 40 min", [0]),
    template(3, "Norwegian 4×4", [1, 5]), template(4, "Zone 2 60 min", [2, 4]),
]

@Test func plannerFixtureDecodesElevenRows() throws {
    let rows = try plannerFixture()
    #expect(rows.count == 11)
    #expect(rows.filter { $0.kind == .planSession }.count == 7)
    #expect(rows.filter { $0.kind == .template }.count == 4)
    let day4 = try #require(rows.first { $0.name == "Day 4 Full Upper" })
    #expect(day4.weekdays.isEmpty && day4.sessionId == 4 && day4.templateId == nil && day4.isStrength && day4.liftCount == 6)
    let z2 = try #require(rows.first { $0.name == "Zone 2 40 min" })
    #expect(z2.weekdays == [0] && z2.templateId == 2 && z2.sessionId == nil && !z2.isStrength && z2.editable)
    #expect(z2.garmin?.workoutId == 901 && z2.onGarmin)
    #expect(rows.first { $0.ref == "t3" }?.onGarmin == false)
}

@Test func plannerDecodesAMinimalRowAndABoolGarminFlag() throws {
    let json = #"[{"ref":"t9","kind":"template","name":"Tempo","sport":"running","weekdays":[2],"garmin":true}]"#
    let rows = try JSON.decoder.decode([PlannerWorkout].self, from: Data(json.utf8))
    #expect(rows[0].onGarmin && rows[0].garmin == nil && rows[0].liftCount == 0 && rows[0].summary == nil && rows[0].editable == false)
    // An unknown kind from a newer hub still decodes (never fails the whole list).
    let odd = #"[{"ref":"x1","kind":"block","name":"X","sport":"strength","weekdays":[]}]"#
    #expect(try JSON.decoder.decode([PlannerWorkout].self, from: Data(odd.utf8))[0].kind == .other)
}

/// PL-3 exit: the 404 fallback yields the same 11 rows from the cached exercises + plan + templates.
@Test func oldHubFallbackYieldsTheSameElevenRows() throws {
    let hub = try plannerFixture()
    let fallback = plannerWorkoutsFallback(exercises: cachedExercises(), planSessions: cachedPlanSessions, templates: cachedTemplates)
    #expect(fallback.map(\.ref) == hub.map(\.ref))
    #expect(fallback.map(\.name) == hub.map(\.name))
    #expect(fallback.map(\.kind) == hub.map(\.kind))
    #expect(fallback.map(\.sport) == hub.map(\.sport))
    #expect(fallback.map(\.weekdays) == hub.map(\.weekdays))
    #expect(fallback.map(\.liftCount) == hub.map(\.liftCount))
    #expect(fallback.map(\.editable) == hub.map(\.editable))
}

/// No plan-session list cached (an even older hub): the exercise rows still give the strength days.
@Test func fallbackWithoutPlanListUsesTheExerciseRows() {
    let rows = plannerWorkoutsFallback(exercises: cachedExercises(), planSessions: [], templates: cachedTemplates)
    #expect(rows.map(\.ref) == ["s1", "s2", "s3", "s4", "t1", "t2", "t3", "t4"])
    #expect(rows.first { $0.ref == "s4" }?.weekdays == [])
}

@Test func plannerUnavailableIsTheDefault() async {
    struct Bare: PlannerProviding {}
    await #expect(throws: PlannerWorkoutsUnavailable.self) { _ = try await Bare().plannerWorkouts() }
}

/// W-B88: the mock serves the post-073 hub — every row a template; the 4 strength days are their
/// library workouts (t5…t8), each linked to its plan session (`linked_refs ["s<id>"]`).
@Test func mockServesThePost073ShapeFromItsFixtures() async throws {
    let rows = try await MockDataProvider().plannerWorkouts()
    #expect(rows.count == 8 && rows.allSatisfy { $0.kind == .template })
    let strength = rows.filter(\.isStrength)
    #expect(strength.map(\.ref) == ["t5", "t6", "t7", "t8"])
    #expect(strength.allSatisfy { !$0.editable && $0.linkedSessionIds.count == 1 && $0.strengthSessionId != nil })
    #expect(strength.first?.liftCount ?? 0 > 0)
}

@Test func strengthDaysAsTemplatesKeepsCardioAndLinksEachSession() {
    let rows = [
        PlannerWorkout(ref: "s1", kind: .planSession, name: "Day 1 Full Upper", sport: "strength", weekdays: [0], liftCount: 6, editable: false),
        PlannerWorkout(ref: "s:Mystery", kind: .planSession, name: "Mystery", sport: "strength", weekdays: [], liftCount: 2, editable: false),
        PlannerWorkout(ref: "t3", kind: .template, name: "Tempo", sport: "running", weekdays: [1], editable: true),
    ]
    let out = plannerStrengthDaysAsTemplates(rows)
    #expect(out.map(\.ref) == ["t3", "t4", "s:Mystery"])
    #expect(out[1].linkedRefs == ["s1"] && out[1].weekdays == [0] && out[1].liftCount == 6 && out[1].summary == "6 lifts" && !out[1].editable)
}

/// PL-8 (verifier fix): a template row names the cardio sessions linked to it by id
/// (`linked_refs`, HT migration 060) — the phone links session ↔ template by that, never by name.
@Test func plannerDecodesLinkedRefsAsSessionIds() throws {
    let json = #"[{"ref":"t3","kind":"template","name":"Norwegian 4×4","sport":"running","weekdays":[1,5],"editable":true,"linked_refs":["s5","s8"]},{"ref":"s1","kind":"plan_session","name":"Day 1","sport":"strength","weekdays":[0]}]"#
    let rows = try JSON.decoder.decode([PlannerWorkout].self, from: Data(json.utf8))
    #expect(rows[0].linkedRefs == ["s5", "s8"] && rows[0].linkedSessionIds == [5, 8])
    #expect(rows[1].linkedRefs.isEmpty)
    #expect(plannerSessionTemplateLinks(rows) == [5: 3, 8: 3])
    // Round-trips through the cache.
    let again = try JSON.decoder.decode([PlannerWorkout].self, from: JSON.encoder.encode(rows))
    #expect(again == rows)
}

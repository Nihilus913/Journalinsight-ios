import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-B88 B88-5 — the post-073 hub: every row is a template. A strength day (t5…t8) is the library
// workout of its plan session (linked_refs ["s1"] …): the row opens the strength detail for that
// session (Log sets unchanged), carries the template id for Send to Watch / Garmin push, filters as
// Strength, and a drag / pick moves the SESSION's one weekday (PL-8 path), never the template's.

func b88StrengthTemplate(_ name: String, id: Int) -> WorkoutTemplate {
    WorkoutTemplate(templateId: id, name: name, activity: "strength", location: .indoor, weekdays: [], steps: [],
                    updatedAt: "2026-10-04T12:00:00Z",
                    segments: [WorkoutSegment(sport: .strength, steps: (0..<6).map { i in
                        .strength(StrengthStep(exerciseKey: "Lift \(i)", garminCategory: "TOTAL_BODY", sets: 3, reps: 8, weightKg: 40, restSeconds: 90))
                    })])
}

let b88Library = plannerLibrary + [
    b88StrengthTemplate("Day 1 Full Upper", id: 5), b88StrengthTemplate("Day 2 Full Upper", id: 6),
    b88StrengthTemplate("Day 3 Full Upper", id: 7), b88StrengthTemplate("Day 4 Full Upper", id: 8),
]

/// The post-073 hub answer (HT B88-3 golden): the running templates (cardio links as PL-8), then
/// one strength template per day, each linked to its session; no plan_session rows.
func b88HubRows() -> [PlannerWorkout] {
    let running = plannerLinkedHubRows().filter { $0.kind == .template }
    let days: [(Int, Int, String, [Int])] = [(5, 1, "Day 1 Full Upper", [0]), (6, 2, "Day 2 Full Upper", [2]),
                                              (7, 3, "Day 3 Full Upper", [4]), (8, 4, "Day 4 Full Upper", [])]
    return running + days.map { tid, sid, name, wd in
        PlannerWorkout(ref: "t\(tid)", kind: .template, name: name, sport: "strength", weekdays: wd, liftCount: 6,
                       summary: "6 lifts", editable: false, linkedRefs: ["s\(sid)"])
    }
}

@MainActor
private func b88VM() async throws -> (TrainingViewModel, PlannerHub) {
    let hub = PlannerHub(templates: b88Library)
    hub.planner = b88HubRows()
    let vm = makePlannerVM(hub, cache: OfflineCache(db: try AppDatabase.inMemory()), outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()
    await vm.library?.load()
    return (vm, hub)
}

@Test func b88AStrengthTemplateRowOpensItsSessionsDetail() {
    let row = b88HubRows().first { $0.ref == "t5" }!
    let ref = PlannerStrengthRef(row)
    #expect(ref.sessionId == 1 && ref.templateId == 5 && ref.name == "Day 1 Full Upper" && ref.weekdays == [0])
    #expect(plannerOpensStrengthDetail(row))
    // a cardio template opens the editor; an old hub's session row still opens the detail
    #expect(!plannerOpensStrengthDetail(b88HubRows().first { $0.ref == "t3" }!))
    #expect(plannerOpensStrengthDetail(plannerHubRows().first { $0.ref == "s1" }!))
    #expect(PlannerStrengthRef(plannerHubRows().first { $0.ref == "s1" }!).templateId == nil)
    let lifts = plannerStrengthLifts(ref, exercises: plannerExercises(), progressions: [])
    #expect(lifts.count == 6)
}

@Test func b88StrengthFilterIsTheFourDaysAndDay4IsNotOnADay() {
    let rows = b88HubRows()
    #expect(plannerFiltered(rows, .strength, templates: b88Library).map(\.ref) == ["t5", "t6", "t7", "t8"])
    #expect(plannerFiltered(rows, .unassigned, templates: b88Library).map(\.name) == ["Day 4 Full Upper"])
    #expect(plannerFiltered(rows, .run, templates: b88Library).map(\.ref) == ["t1", "t2", "t3", "t4"])
    for f in PlannerFilter.allCases { #expect(!plannerFiltered(rows, f, templates: b88Library).isEmpty, "\(f.rawValue) is empty") }
}

@Test @MainActor func b88TheVMListsTheStrengthDaysOnTheirSessionsDays() async throws {
    let (vm, _) = try await b88VM()
    let rows = vm.plannerWorkouts
    #expect(rows.map(\.ref) == ["t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8"])
    #expect(rows.first { $0.ref == "t5" }?.weekdays == [0])
    #expect(rows.first { $0.ref == "t8" }?.weekdays == [])
    #expect(vm.dayPreview(weekday: 0).entries.map(\.title).contains("Day 1 Full Upper"))
}

@Test @MainActor func b88DraggingAStrengthDayMovesItsSession() async throws {
    let (vm, hub) = try await b88VM()
    let writes = plannerDropWrites(PlannerDragItem(ref: "t8"), toWeekday: 6, spine: vm.daySpine, templates: b88Library)
    #expect(writes == [.sessionWeekday(id: 4, name: "Day 4 Full Upper", weekday: 6)])
    #expect(plannerDropWrites(PlannerDragItem(ref: "t5", fromWeekday: 0), toWeekday: 0, spine: vm.daySpine, templates: b88Library).isEmpty)
    let result = await vm.drop(PlannerDragItem(ref: "t5", fromWeekday: 0).payload, onDay: 3)
    #expect(result == .saved)
    #expect(hub.weekdayCalls.map(\.0) == [1] && hub.weekdayCalls.map(\.1) == [3])
    #expect(hub.workouts.writes.isEmpty)   // the template's own weekdays are never written
    // cardio templates still add a day (PL-7 unchanged)
    #expect(plannerDropWrites(PlannerDragItem(ref: "t3"), toWeekday: 6, spine: vm.daySpine, templates: b88Library)
            == [.templateWeekdays(b88Library[2], [1, 5, 6])])
}

@Test @MainActor func b88PickingAStrengthDayOnADayMovesItsSession() async throws {
    let (vm, _) = try await b88VM()
    let opt = try #require(vm.plannerOptions(weekday: 3).first { $0.id == "t5" })
    #expect(opt.choice == .planSession(id: 1, name: "Day 1 Full Upper"))
    #expect(opt.currentDays == [0] && !opt.isOnThisDay && opt.kind == .strength)
}

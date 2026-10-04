import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-PLANNER PL-8 (verifier fix) — the phone links a cardio plan session to its workout template
// by id (`/planning/workouts` `linked_refs`, HT migration 060), never by name. A linked session IS
// its template: the day shows the template's name once (Tue = "Norwegian 4×4" only), and the
// template's row lists the linked sessions' days (Long Run Zone 2 = Thu, as the hub says).

/// The post-060 hub answer: the linked cardio sessions (s5 Tue, s6 Thu, s8 Sat) are not listed;
/// their templates carry them in `linked_refs` and their days in `weekdays`.
func plannerLinkedHubRows(longRunDays: [Int] = [6]) -> [PlannerWorkout] {
    plannerHubRows().compactMap { row in
        var row = row
        switch row.ref {
        case "s5", "s6", "s8": return nil
        case "t1": row.linkedRefs = ["s6"]; row.weekdays = Array(Set(longRunDays + [3])).sorted()
        case "t3": row.linkedRefs = ["s5", "s8"]
        default: break
        }
        return row
    }
}

@MainActor
private func linkedVM(longRunDays: [Int] = [6]) async throws -> TrainingViewModel {
    var lib = plannerLibrary
    lib[0].weekdays = longRunDays
    let hub = PlannerHub(templates: lib)
    hub.planner = plannerLinkedHubRows(longRunDays: longRunDays)
    let vm = makePlannerVM(hub, cache: OfflineCache(db: try AppDatabase.inMemory()), outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()
    await vm.library?.load()
    return vm
}

@Test @MainActor func aLinkedCardioSessionShowsAsItsTemplateOnce() async throws {
    let vm = try await linkedVM()
    #expect(vm.dayPreview(weekday: 1).entries.map(\.title) == ["Norwegian 4×4"])
    #expect(vm.dayPreview(weekday: 5).entries.map(\.title) == ["Norwegian 4×4"])
    #expect(vm.dayPreview(weekday: 3).entries.map(\.title) == ["Long Run Zone 2"])
    // Still the plan session underneath (Change / Take off write its weekday).
    #expect(vm.dayPreview(weekday: 1).entries[0].choice == .planSession(id: 5, name: "Norwegian 4×4"))
    // The week strip names the same workout, with no duplicate extra.
    let tue = vm.weekSummary.days[1]
    #expect(tue.sessionName == "Norwegian 4×4" && tue.extras.isEmpty)
    #expect(vm.weekSummary.days[3].sessionName == "Long Run Zone 2" && vm.weekSummary.days[3].extras.isEmpty)
}

@Test @MainActor func aTemplatesRowListsItsLinkedSessionsDays() async throws {
    // PL-10 state on :8281: the Long Run template on no day of its own, its Thursday session linked.
    let vm = try await linkedVM(longRunDays: [])
    let longRun = try #require(vm.plannerWorkouts.first { $0.ref == "t1" })
    #expect(longRun.weekdays == [3])
    #expect(!plannerFiltered(vm.plannerWorkouts, .unassigned, templates: vm.library?.templates ?? []).contains { $0.ref == "t1" })
    #expect(!vm.dayPreview(weekday: 6).entries.map(\.title).contains("Long Run Zone 2"))
    #expect(vm.plannerWorkouts.first { $0.ref == "t3" }?.weekdays == [1, 5])
}

private let linkSpine = [
    WeekSpineEntry(id: 1, name: "Day 1 Full Upper", weekday: 0),
    WeekSpineEntry(id: 5, name: "Interval Run", weekday: 1, kind: .interval, templateId: 3),
    WeekSpineEntry(id: 8, name: "Interval Run 2", weekday: 5, kind: .interval, templateId: 3),
]

@Test func takingALinkedSessionOffADayTakesItsTemplateOffThatDayToo() {
    let t3 = plannerLibrary[2]   // Norwegian 4×4 [Tue, Sat]
    let w = trainingDayWrites(weekday: 1, adding: nil, removing: .session(id: 5, name: "Norwegian 4×4", kind: .interval),
                              spine: linkSpine, templates: plannerLibrary)
    #expect(w == [.sessionWeekday(id: 5, name: "Interval Run", weekday: nil), .templateWeekdays(t3, [5])])
}

@Test func aSessionAndATemplateAreNeverLinkedByName() {
    // Same name, no id link → two workouts (the B-40 name match is retired, PL-8).
    let t = plannerTemplate("day 1 full upper", id: 9, weekdays: [3])
    let o = trainingDayOptions(weekday: 3, spine: linkSpine, templates: [t, plannerLibrary[2]])
    #expect(o.library[0].choice == .template(t))
    #expect(o.plan.map(\.id) == ["s1"])   // the linked sessions are their template's row
    let p = trainingDayPreview(day: TrainingWeekDay(weekday: 3, date: "2026-10-08", kind: .rest, sessionName: nil, sessionId: nil, done: nil, isToday: false),
                               spine: linkSpine, exercises: [], templates: [t])
    #expect(p.entries.map(\.title) == ["day 1 full upper"])
}

@Test func theLinkMapComesFromTheHubRows() {
    #expect(plannerSessionTemplateLinks(plannerLinkedHubRows()) == [5: 3, 6: 1, 8: 3])
    let linked = plannerLinkingSpine(linkSpine.map { WeekSpineEntry(id: $0.id, name: $0.name, weekday: $0.weekday, kind: $0.kind) },
                                     links: [5: 3, 8: 3])
    #expect(linked == linkSpine)
}

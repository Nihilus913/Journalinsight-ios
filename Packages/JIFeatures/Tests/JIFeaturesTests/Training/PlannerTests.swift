import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-PLANNER (PL-3 … PL-7) — one Planner: this week + every workout, assigned or not.
// Data = the PL-1 shape in the Wave Card (prod plan 2026-10-04): Day 1–3 Full Upper Mon/Wed/Fri,
// Day 4 unassigned, cardio sessions Tue/Thu/Sat, Rest; templates Long Run Zone 2 [Sun],
// Zone 2 40 min [Mon], Norwegian 4×4 [Tue, Sat], Zone 2 60 min [Wed, Fri].

func plannerTemplate(_ name: String, id: Int, weekdays: [Int], minutes: Int = 40) -> WorkoutTemplate {
    WorkoutTemplate(templateId: id, name: name, activity: "running", location: .outdoor, weekdays: weekdays, steps: [],
                    updatedAt: "2026-10-01T08:00:00Z",
                    segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: minutes * 60), target: .hrZone(2)))])])
}

let plannerLibrary = [
    plannerTemplate("Long Run Zone 2", id: 1, weekdays: [6], minutes: 90),
    plannerTemplate("Zone 2 40 min", id: 2, weekdays: [0]),
    plannerTemplate("Norwegian 4×4", id: 3, weekdays: [1, 5], minutes: 30),
    plannerTemplate("Zone 2 60 min", id: 4, weekdays: [2, 4], minutes: 60),
]

let plannerSessions = [
    PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 0, sessionType: "strength"),
    PlanSessionOut(id: 2, name: "Day 2 Full Upper", weekday: 2, sessionType: "strength"),
    PlanSessionOut(id: 3, name: "Day 3 Full Upper", weekday: 4, sessionType: "strength"),
    PlanSessionOut(id: 4, name: "Day 4 Full Upper", weekday: nil, sessionType: "strength"),
    PlanSessionOut(id: 5, name: "Interval Run", weekday: 1, sessionType: "cardio"),
    PlanSessionOut(id: 6, name: "Long Zone 2", weekday: 3, sessionType: "cardio"),
    PlanSessionOut(id: 7, name: "Rest", weekday: 6, sessionType: "rest"),
    PlanSessionOut(id: 8, name: "Interval Run 2", weekday: 5, sessionType: "cardio"),
]

func plannerExercises() -> [Exercise] {
    plannerSessions.prefix(4).flatMap { s in
        (0..<6).map { i in
            Exercise(exerciseId: s.id * 10 + i, sessionName: s.name, exerciseName: "Lift \(i)", sets: 3, repsTarget: "8",
                     currentWeightKg: 40, progressionStepKg: 2.5, weekday: s.weekday, sessionId: s.id)
        }
    }
}

/// The PL-1 answer for that plan (what `/planning/workouts` serves).
func plannerHubRows() -> [PlannerWorkout] {
    plannerWorkoutsFallback(exercises: plannerExercises(), planSessions: plannerSessions, templates: plannerLibrary)
}

/// Training + plan_weekday + library + planner routes — the shape `HubDataProvider` has.
nonisolated final class PlannerHub: TrainingProviding, PlanSessionWeekdayProviding, WorkoutLibraryProviding, PlannerProviding, @unchecked Sendable {
    let workouts: FakeWorkoutHub
    var rows = plannerExercises()
    var sessions = plannerSessions
    /// nil = an older hub: `/planning/workouts` answers 404.
    var planner: [PlannerWorkout]? = plannerHubRows()
    var offline = false
    var weekdayCalls: [(Int, Int?)] = []
    init(templates: [WorkoutTemplate] = plannerLibrary) { workouts = FakeWorkoutHub(rows: templates) }

    func plannerWorkouts() async throws -> [PlannerWorkout] {
        if offline { throw HubError.network("offline") }
        guard let planner else { throw PlannerWorkoutsUnavailable() }
        return planner
    }
    func planSessions() async throws -> [PlanSessionOut] {
        if offline { throw HubError.network("offline") }
        return sessions
    }
    func trainingDay(date: String) async throws -> TrainingDayDetail {
        if offline { throw HubError.network("offline") }
        return TrainingDayDetail(date: date, activities: [], exerciseSets: [])
    }
    func exercises() async throws -> [Exercise] {
        if offline { throw HubError.network("offline") }
        return rows
    }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut {
        if offline { throw HubError.network("offline") }
        weekdayCalls.append((sessionId, weekday))
        for i in rows.indices where rows[i].sessionId == sessionId { rows[i].weekday = weekday }
        if let i = sessions.firstIndex(where: { $0.id == sessionId }) { sessions[i].weekday = weekday }
        return PlanSessionOut(id: sessionId, name: sessions.first { $0.id == sessionId }?.name ?? "", weekday: weekday)
    }
    func workoutTemplates() async throws -> [WorkoutTemplate] {
        workouts.readsFail = offline; return try await workouts.workoutTemplates()
    }
    func createWorkoutTemplate(_ d: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        workouts.writeError = offline ? HubError.network("offline") : nil; return try await workouts.createWorkoutTemplate(d)
    }
    func updateWorkoutTemplate(id: Int, _ d: WorkoutTemplateDraft) async throws -> WorkoutTemplate {
        workouts.writeError = offline ? HubError.network("offline") : nil; return try await workouts.updateWorkoutTemplate(id: id, d)
    }
    func deleteWorkoutTemplate(id: Int) async throws { try await workouts.deleteWorkoutTemplate(id: id) }
    func pushWorkoutTemplateToGarmin(id: Int) async throws -> GarminPushResult { try await workouts.pushWorkoutTemplateToGarmin(id: id) }
    func importWorkoutsFromGarmin() async throws -> GarminImportReport { try await workouts.importWorkoutsFromGarmin() }
}

/// Monday 2026-10-05, 08:00 UTC.
@MainActor
func makePlannerVM(_ hub: PlannerHub, cache: OfflineCache, outbox: Outbox) -> TrainingViewModel {
    TrainingViewModel(
        provider: hub, healthProvider: MockDataProvider(), cache: cache,
        strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "planner.\(UUID().uuidString)")),
        outbox: outbox,
        drainer: OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub),
        now: { ISO8601DateFormatter().date(from: "2026-10-05T08:00:00Z")! }
    )
}

// MARK: - PL-3: one list, hub or old-hub fallback, cached

@Test @MainActor func plannerListsTheHubsElevenRowsAndCachesThem() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = makePlannerVM(PlannerHub(), cache: cache, outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.plannerWorkouts.count == 11)
    #expect(vm.plannerWorkouts.map(\.ref) == plannerHubRows().map(\.ref))
    #expect(try cache.get(TrainingViewModel.plannerCacheKey, as: [PlannerWorkout].self)?.value.count == 11)
}

@Test @MainActor func anOldHub404GivesTheSameElevenRowsFromTheCachedRows() async throws {
    let hub = PlannerHub()
    hub.planner = nil
    let vm = makePlannerVM(hub, cache: OfflineCache(db: try AppDatabase.inMemory()), outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.hubPlannerWorkouts == nil)
    #expect(vm.plannerWorkouts.map(\.ref) == plannerHubRows().map(\.ref))
    #expect(vm.plannerWorkouts.map(\.weekdays) == plannerHubRows().map(\.weekdays))
}

@Test @MainActor func offlineColdLaunchShowsTheCachedList() async throws {
    let db = try AppDatabase.inMemory()
    let cache = OfflineCache(db: db)
    let first = makePlannerVM(PlannerHub(), cache: cache, outbox: Outbox(db: try AppDatabase.inMemory()))
    await first.load()
    let hub = PlannerHub()
    hub.offline = true
    let second = makePlannerVM(hub, cache: cache, outbox: Outbox(db: try AppDatabase.inMemory()))
    await second.load()
    #expect(second.plannerWorkouts.count == 11)
}

@Test func rowsFollowThisPhonesDayChanges() {
    var spine = trainingDaySpine(strength: weekSpine(planSessions: Array(plannerSessions.prefix(4)), exercises: plannerExercises()), sessions: plannerSessions)
    if let i = spine.firstIndex(where: { $0.id == 4 }) { spine[i] = WeekSpineEntry(id: 4, name: "Day 4 Full Upper", weekday: 6) }
    var lib = plannerLibrary
    lib[0].weekdays = []
    let rows = plannerWorkoutRows(hub: plannerHubRows(), exercises: plannerExercises(), planSessions: plannerSessions, spine: spine,
                                  templates: lib, libraryLoaded: true)
    #expect(rows.first { $0.ref == "s4" }?.weekdays == [6])
    #expect(rows.first { $0.ref == "t1" }?.weekdays == [])
    // A template made on this phone (negative id, queued) is listed; one the library dropped is not.
    lib.append(plannerTemplate("Tempo", id: -1, weekdays: []))
    lib.removeAll { $0.templateId == 4 }
    let more = plannerWorkoutRows(hub: plannerHubRows(), exercises: [], planSessions: [], spine: spine, templates: lib, libraryLoaded: true)
    #expect(more.contains { $0.ref == "t-1" } && !more.contains { $0.ref == "t4" })
}

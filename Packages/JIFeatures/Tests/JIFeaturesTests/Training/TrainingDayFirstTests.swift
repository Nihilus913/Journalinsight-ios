import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// W-B40 L3 (B-82) — Training day-first: tap a day → preview of that day's session(s) → change =
// pick from the plan sessions + the B-40 workout library. A plan session's day is written through
// `PUT /planning/plan-sessions/{id}` (Outbox kind `plan_weekday`, B-52); a library workout's day is
// the B-40 template↔day link (`weekdays`), written through the library's own queued write (kind
// `workout_template`). Both are offline-first: queued before the hub is asked, drained later.

private func run(_ name: String, id: Int, weekdays: [Int] = [], minutes: Int = 40) -> WorkoutTemplate {
    WorkoutTemplate(templateId: id, name: name, activity: "running", location: .outdoor, weekdays: weekdays, steps: [],
                    updatedAt: "2026-09-28T08:00:00Z",
                    segments: [WorkoutSegment(sport: .running, steps: [.cardio(CardioStep(purpose: .work, end: .time(seconds: minutes * 60), target: .hrZone(2)))])])
}

private func lift(_ id: Int, _ session: String, weekday: Int?, sessionId: Int?) -> Exercise {
    Exercise(exerciseId: id, sessionName: session, exerciseName: "Lift \(id)", sets: 3, repsTarget: "8",
             currentWeightKg: 50, progressionStepKg: 2.5, weekday: weekday, sessionId: sessionId)
}

private let spine = [
    WeekSpineEntry(id: 1, name: "Day 1 Full Upper", weekday: 0),
    WeekSpineEntry(id: 2, name: "Day 2 Full Upper", weekday: 2),
    WeekSpineEntry(id: 4, name: "Day 4 Full Upper", weekday: nil),
]
private let library = [
    run("Zone 2 60 min", id: 4, weekdays: [2, 4], minutes: 60),
    run("Norwegian 4×4", id: 3, weekdays: [1, 5]),
    run("Long Run Zone 2", id: 1, weekdays: [6], minutes: 90),
]

private func day(_ wd: Int, kind: TrainingWeekDayKind = .rest, name: String? = nil) -> TrainingWeekDay {
    TrainingWeekDay(weekday: wd, date: "2026-09-2\(8 + wd)", kind: kind, sessionName: name, sessionId: nil, done: nil, isToday: false)
}

// MARK: - Preview: that day's session

@Test func previewShowsTheStrengthSessionWithItsLiftsAndTheRunsOnThatDay() {
    let rows = [lift(10, "Day 2 Full Upper", weekday: 2, sessionId: 2), lift(11, "Day 2 Full Upper", weekday: 2, sessionId: 2),
                lift(12, "Day 1 Full Upper", weekday: 0, sessionId: 1)]
    let p = trainingDayPreview(day: day(2, kind: .strength, name: "Day 2 Full Upper"), spine: spine, exercises: rows, templates: library)
    #expect(p.entries.count == 2)
    guard case .strength(let id, let name, let lifts) = p.entries[0] else { Issue.record("strength first"); return }
    #expect(id == 2 && name == "Day 2 Full Upper" && lifts.map(\.exerciseId) == [10, 11])
    guard case .template(let t) = p.entries[1] else { Issue.record("then the run"); return }
    #expect(t.name == "Zone 2 60 min")
    #expect(!p.isRest)
}

@Test func previewFallsBackToTheMorningCallScheduleOnlyWhenNothingIsAssigned() {
    let empty = trainingDayPreview(day: day(3, kind: .longRun, name: "Long Z2"), spine: spine, exercises: [], templates: library)
    #expect(empty.entries == [.scheduled(name: "Long Z2", kind: .longRun)])
    // B40-V1: a library run on the day is ADDED — it never hides the day's scheduled session.
    let tue = trainingDayPreview(day: day(1, kind: .interval, name: "Intervals"), spine: spine, exercises: [], templates: library)
    #expect(tue.entries.map(\.title) == ["Intervals", "Norwegian 4×4"])
}

// MARK: - B40-V1: the plan's cardio / rest sessions are changeable

private let hubSessions = [
    PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 0, sessionType: "strength"),
    PlanSessionOut(id: 5, name: "Interval Run", weekday: 5, sessionType: "cardio"),
    PlanSessionOut(id: 6, name: "Long Zone 2", weekday: 3, sessionType: "cardio"),
    PlanSessionOut(id: 7, name: "Rest", weekday: nil, sessionType: "rest"),
]
private let fullSpine = trainingDaySpine(strength: spine, sessions: hubSessions)

@Test func theDaySpineAddsThePlansCardioAndRestSessionsOnce() {
    #expect(fullSpine.map(\.name) == ["Day 1 Full Upper", "Day 2 Full Upper", "Day 4 Full Upper", "Interval Run", "Long Zone 2", "Rest"])
    #expect(fullSpine.map(\.kind) == [.strength, .strength, .strength, .interval, .longRun, .rest])
    #expect(trainingDaySpine(strength: spine, sessions: []) == spine)
}

@Test func addingALibraryWorkoutNeverHidesThePlansCardioSession() {
    let verify = run("Verify Easy 30", id: 9, weekdays: [3], minutes: 30)
    let p = trainingDayPreview(day: day(3, kind: .longRun, name: "Long Zone 2"), spine: fullSpine, exercises: [], templates: [verify])
    #expect(p.entries.map(\.title) == ["Long Zone 2", "Verify Easy 30"])
    #expect(p.entries[0] == .session(id: 6, name: "Long Zone 2", kind: .longRun))
    #expect(p.entries[0].choice == .planSession(id: 6, name: "Long Zone 2"))   // Change + Take off
}

@Test func thePickerOffersThePlansCardioAndRestSessions() {
    let o = trainingDayOptions(weekday: 2, spine: fullSpine, templates: library)
    #expect(o.plan.map(\.title) == ["Day 1 Full Upper", "Day 2 Full Upper", "Day 4 Full Upper", "Interval Run", "Long Zone 2", "Rest"])
    #expect(o.plan.map(\.kind) == [.strength, .strength, .strength, .interval, .longRun, .rest])
    #expect(o.plan[4].currentDays == [3])
}

@Test func aCardioSessionMovesAndComesOffThroughItsPlanSession() {
    #expect(trainingDayWrites(weekday: 3, adding: nil, removing: .session(id: 6, name: "Long Zone 2", kind: .longRun), spine: fullSpine, templates: library)
            == [.sessionWeekday(id: 6, name: "Long Zone 2", weekday: nil)])
    #expect(trainingDayWrites(weekday: 4, adding: .planSession(id: 6, name: "Long Zone 2"), removing: nil, spine: fullSpine, templates: library)
            == [.sessionWeekday(id: 6, name: "Long Zone 2", weekday: 4)])
}

@Test func sessionKindComesFromTheHubsSessionType() {
    #expect(trainingSessionKind(type: "cardio", name: "Interval Run") == .interval)
    #expect(trainingSessionKind(type: "cardio", name: "Norwegian 4x4") == .interval)
    #expect(trainingSessionKind(type: "cardio", name: "Long Zone 2") == .longRun)
    #expect(trainingSessionKind(type: "rest", name: "Rest") == .rest)
    #expect(trainingSessionKind(type: "strength", name: "Day 1") == .strength)
    #expect(trainingSessionKind(type: nil, name: "Day 1") == .strength)
}

@Test func aRestDayHasNoEntriesAndSaysSo() {
    let p = trainingDayPreview(day: day(3), spine: spine, exercises: [], templates: [])
    #expect(p.isRest && p.entries.isEmpty)
}

// MARK: - Picker: the plan sessions + the workout library

@Test func pickerListsThePlanSessionsAndTheWholeLibrary() {
    let o = trainingDayOptions(weekday: 2, spine: spine, templates: library)
    #expect(o.plan.map(\.title) == ["Day 1 Full Upper", "Day 2 Full Upper", "Day 4 Full Upper"])
    #expect(o.library.map(\.title) == ["Zone 2 60 min", "Norwegian 4×4", "Long Run Zone 2"])
    #expect(o.plan.map(\.isOnThisDay) == [false, true, false])
    #expect(o.library.map(\.isOnThisDay) == [true, false, false])
    #expect(o.plan[0].currentDays == [0] && o.plan[2].currentDays == [])
    #expect(o.library[0].currentDays == [2, 4])
}

@Test func aLibraryWorkoutNamedLikeAPlanSessionIsThatSessionNotASecondRow() {
    let t = run("day 1 full upper", id: 9)
    let o = trainingDayOptions(weekday: 3, spine: spine, templates: [t])
    #expect(o.plan.map(\.title) == ["Day 2 Full Upper", "Day 4 Full Upper"])
    #expect(o.library.count == 1)
    #expect(o.library[0].choice == .planSession(id: 1, name: "Day 1 Full Upper"))
    #expect(o.library[0].currentDays == [0])
}

// MARK: - Writes: what one pick changes

@Test func addingAPlanSessionMovesThatSessionOnly() {
    let w = trainingDayWrites(weekday: 3, adding: .planSession(id: 4, name: "Day 4 Full Upper"), removing: nil, spine: spine, templates: library)
    #expect(w == [.sessionWeekday(id: 4, name: "Day 4 Full Upper", weekday: 3)])
}

@Test func addingALibraryWorkoutAddsTheDayAndKeepsItsOtherDays() {
    let w = trainingDayWrites(weekday: 0, adding: .template(library[0]), removing: nil, spine: spine, templates: library)
    #expect(w == [.templateWeekdays(library[0], [0, 2, 4])])
}

@Test func changingAnEntryReplacesOnlyThatEntry() {
    // Wed: Day 2 + Zone 2 60. Change the run to Norwegian 4×4: the lift stays.
    let w = trainingDayWrites(weekday: 2, adding: .template(library[1]), removing: .template(library[0]), spine: spine, templates: library)
    #expect(w == [.templateWeekdays(library[0], [4]), .templateWeekdays(library[1], [1, 2, 5])])
    // Change the lift to Day 4: Day 2 comes off Wednesday (stays in the plan), the run stays.
    let s = trainingDayWrites(weekday: 2, adding: .planSession(id: 4, name: "Day 4 Full Upper"),
                              removing: .strength(id: 2, name: "Day 2 Full Upper", lifts: []), spine: spine, templates: library)
    #expect(s == [.sessionWeekday(id: 2, name: "Day 2 Full Upper", weekday: nil), .sessionWeekday(id: 4, name: "Day 4 Full Upper", weekday: 2)])
}

@Test func removingTakesTheEntryOffThisDayOnly() {
    #expect(trainingDayWrites(weekday: 4, adding: nil, removing: .template(library[0]), spine: spine, templates: library)
            == [.templateWeekdays(library[0], [2])])
    #expect(trainingDayWrites(weekday: 0, adding: nil, removing: .strength(id: 1, name: "Day 1 Full Upper", lifts: []), spine: spine, templates: library)
            == [.sessionWeekday(id: 1, name: "Day 1 Full Upper", weekday: nil)])
}

@Test func pickingWhatIsAlreadyThereWritesNothing() {
    #expect(trainingDayWrites(weekday: 2, adding: .template(library[0]), removing: .template(library[0]), spine: spine, templates: library).isEmpty)
    #expect(trainingDayWrites(weekday: 2, adding: .template(library[0]), removing: nil, spine: spine, templates: library).isEmpty)
    #expect(trainingDayWrites(weekday: 0, adding: .planSession(id: 1, name: "Day 1 Full Upper"), removing: nil, spine: spine, templates: library).isEmpty)
    // The fixed schedule is not ours to remove.
    #expect(trainingDayWrites(weekday: 3, adding: nil, removing: .scheduled(name: "Long Z2", kind: .longRun), spine: spine, templates: library).isEmpty)
}

@Test func aStaleTemplateInTheChoiceUsesTheLibrarysCurrentDays() {
    let stale = run("Zone 2 60 min", id: 4, weekdays: [], minutes: 60)
    #expect(trainingDayWrites(weekday: 0, adding: .template(stale), removing: nil, spine: spine, templates: library)
            == [.templateWeekdays(library[0], [0, 2, 4])])
}

// MARK: - View model: offline-first through both queues

/// Training + plan_weekday + the library routes — the shape `HubDataProvider` has.
nonisolated final class DayFirstHub: TrainingProviding, PlanSessionWeekdayProviding, WorkoutLibraryProviding, @unchecked Sendable {
    let workouts: FakeWorkoutHub
    var rows: [Exercise] = [
        Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3, repsTarget: "8",
                 currentWeightKg: 50, progressionStepKg: 2.5, weekday: 0, sessionId: 7),
        Exercise(exerciseId: 2, sessionName: "Day 2 Full Upper", exerciseName: "Row", sets: 3, repsTarget: "10",
                 currentWeightKg: 40, progressionStepKg: 2.5, weekday: nil, sessionId: 8),
    ]
    var offline = false
    var weekdayCalls: [(Int, Int?)] = []
    /// `GET /planning/plan-sessions` (nil = an older hub without the route).
    var allSessions: [PlanSessionOut]?
    init(templates: [WorkoutTemplate]) { workouts = FakeWorkoutHub(rows: templates) }

    func planSessions() async throws -> [PlanSessionOut] {
        if offline { throw HubError.network("offline") }
        guard let allSessions else { throw PlanSessionListUnavailable() }
        return allSessions
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
        if let i = allSessions?.firstIndex(where: { $0.id == sessionId }) { allSessions?[i].weekday = weekday }
        return PlanSessionOut(id: sessionId, name: rows.first { $0.sessionId == sessionId }?.sessionName ?? "", weekday: weekday)
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

@MainActor
private func makeVM(_ hub: DayFirstHub, outbox: Outbox, cache: OfflineCache) -> TrainingViewModel {
    TrainingViewModel(
        provider: hub, healthProvider: MockDataProvider(), cache: cache,
        strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "b82.\(UUID().uuidString)")),
        outbox: outbox,
        drainer: OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub),
        now: { ISO8601DateFormatter().date(from: "2026-09-28T08:00:00Z")! }
    )
}

@Test @MainActor func theTrainingModelOwnsTheLibraryWhenTheHubServesIt() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = makeVM(DayFirstHub(templates: library), outbox: Outbox(db: try AppDatabase.inMemory()), cache: cache)
    await vm.load()
    #expect(vm.library?.templates.map(\.name) == library.map(\.name))
    // A provider without the library routes (fixtures / mock data) has none — no fake list.
    let plain = TrainingViewModel(provider: PlanWeekdayFakeProvider(), healthProvider: MockDataProvider(), cache: cache)
    #expect(plain.library == nil)
}

@Test @MainActor func pickingAPlanSessionForADayGoesThroughPlanWeekday() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = DayFirstHub(templates: library)
    let vm = makeVM(hub, outbox: outbox, cache: cache)
    await vm.load()

    let result = await vm.changeDay(weekday: 3, adding: .planSession(id: 8, name: "Day 2 Full Upper"), removing: nil)

    #expect(result == .saved)
    #expect(hub.weekdayCalls.count == 1 && hub.weekdayCalls[0].0 == 8 && hub.weekdayCalls[0].1 == 3)
    #expect(vm.dayPreview(weekday: 3).entries.map(\.title).contains("Day 2 Full Upper"))
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func pickingALibraryWorkoutWritesItsDaysThroughTheLibrary() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let hub = DayFirstHub(templates: library)
    let vm = makeVM(hub, outbox: Outbox(db: try AppDatabase.inMemory()), cache: cache)
    await vm.load()

    let result = await vm.changeDay(weekday: 0, adding: .template(library[1]), removing: nil)

    #expect(result == .saved)
    #expect(hub.workouts.writes == ["PUT 3"])
    #expect(hub.workouts.lastDraft?.weekdays == [0, 1, 5])
    #expect(hub.workouts.lastDraft?.name == "Norwegian 4×4")
    #expect(vm.dayPreview(weekday: 0).entries.map(\.title).contains("Norwegian 4×4"))
}

@Test @MainActor func offlinePicksQueueShowAtOnceAndDrainOnReconnect() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = DayFirstHub(templates: library)
    let vm = makeVM(hub, outbox: outbox, cache: cache)
    await vm.load()
    hub.offline = true

    let s = await vm.changeDay(weekday: 3, adding: .planSession(id: 8, name: "Day 2 Full Upper"), removing: nil)
    let t = await vm.changeDay(weekday: 3, adding: .template(library[2]), removing: nil)

    #expect(s == .queued && t == .queued)
    // Nothing reached the hub (the fake logs an attempt that threw, so check the rows it holds).
    #expect(hub.weekdayCalls.isEmpty)
    #expect(hub.workouts.rows.first { $0.templateId == 1 }?.weekdays == [6])
    let kinds = try outbox.pending().map(\.kind).sorted()
    #expect(kinds == [WorkoutLibraryOutbox.kind, OutboxDrainer.planWeekdayKind].sorted())
    // Shown at once, marked pending.
    let thu = vm.dayPreview(weekday: 3)
    #expect(thu.entries.map(\.title) == ["Day 2 Full Upper", "Long Run Zone 2"])
    #expect(vm.isPending(thu.entries[0]) && vm.isPending(thu.entries[1]))

    // Reconnect: the next Training refresh drains both lanes.
    hub.offline = false
    _ = await OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub).drainOnce()
    await vm.refresh()

    #expect(try outbox.pending().isEmpty)
    #expect(hub.weekdayCalls.map(\.0) == [8] && hub.weekdayCalls.map(\.1) == [3])
    #expect(hub.workouts.writes.last == "PUT 1")
    #expect(hub.workouts.rows.first { $0.templateId == 1 }?.weekdays == [3, 6])
    let after = vm.dayPreview(weekday: 3)
    #expect(after.entries.map(\.title) == ["Day 2 Full Upper", "Long Run Zone 2"])
    #expect(!after.entries.contains { vm.isPending($0) })
}

@Test @MainActor func thePlansCardioSessionCanBeTakenOffAndMovedFromTheDaySheet() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let hub = DayFirstHub(templates: library)
    hub.allSessions = [PlanSessionOut(id: 7, name: "Day 1 Full Upper", weekday: 0, sessionType: "strength"),
                       PlanSessionOut(id: 8, name: "Day 2 Full Upper", weekday: nil, sessionType: "strength"),
                       PlanSessionOut(id: 6, name: "Long Zone 2", weekday: 3, sessionType: "cardio")]
    let vm = makeVM(hub, outbox: Outbox(db: try AppDatabase.inMemory()), cache: cache)
    await vm.load()

    #expect(vm.dayOptions(weekday: 2).plan.map(\.title) == ["Day 1 Full Upper", "Day 2 Full Upper", "Long Zone 2"])
    let thu = vm.dayPreview(weekday: 3)
    #expect(thu.entries == [.session(id: 6, name: "Long Zone 2", kind: .longRun)])
    #expect(vm.weekSummary.days[3].kind == .longRun)

    #expect(await vm.changeDay(weekday: 3, adding: nil, removing: thu.entries[0]) == .saved)
    #expect(hub.weekdayCalls.last?.0 == 6 && hub.weekdayCalls.last?.1 == nil)
    #expect(vm.dayPreview(weekday: 3).isRest)
    #expect(vm.weekSummary.days[3].kind == .rest)
    #expect(vm.planSessions.map(\.id) == [7, 8])   // a cardio session never becomes a strength row

    #expect(await vm.changeDay(weekday: 4, adding: .planSession(id: 6, name: "Long Zone 2"), removing: nil) == .saved)
    #expect(vm.weekSummary.days[4].kind == .longRun)
    // A cold relaunch reads it back from the cache.
    let again = makeVM(hub, outbox: Outbox(db: try AppDatabase.inMemory()), cache: cache)
    hub.offline = true
    await again.load()
    #expect(again.dayPreview(weekday: 4).entries.map(\.title).contains("Long Zone 2"))
}

@Test @MainActor func anOlderHubWithoutThePlanSessionListStillShowsTheSchedule() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let vm = makeVM(DayFirstHub(templates: library), outbox: Outbox(db: try AppDatabase.inMemory()), cache: cache)
    await vm.load()
    // Thu 2026-10-01: the morning-call schedule's long run, never dropped.
    #expect(vm.dayPreview(weekday: 3).entries.map(\.title).count == 1)
    guard case .scheduled = vm.dayPreview(weekday: 3).entries.first else { Issue.record("schedule fallback"); return }
}

@Test @MainActor func aRefusedSessionPickIsSaidOutLoudAndRolledBack() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let bad = RefusingWeekdayHub()
    let vm = TrainingViewModel(provider: bad, healthProvider: MockDataProvider(), cache: cache,
                               strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "b82r.\(UUID().uuidString)")),
                               outbox: outbox, drainer: OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: bad),
                               now: { ISO8601DateFormatter().date(from: "2026-09-28T08:00:00Z")! })
    await vm.load()
    let r = await vm.changeDay(weekday: 3, adding: .planSession(id: 7, name: "Day 1 Full Upper"), removing: nil)
    guard case .refused = r else { Issue.record("expected refused, got \(r)"); return }
    #expect(!vm.dayPreview(weekday: 3).entries.map(\.title).contains("Day 1 Full Upper"))
    #expect(vm.dayPreview(weekday: 0).entries.map(\.title) == ["Day 1 Full Upper"])
    #expect(try outbox.pending().isEmpty)
}

nonisolated final class RefusingWeekdayHub: TrainingProviding, PlanSessionWeekdayProviding, @unchecked Sendable {
    func trainingDay(date: String) async throws -> TrainingDayDetail { TrainingDayDetail(date: date, activities: [], exerciseSets: []) }
    func exercises() async throws -> [Exercise] {
        [Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3, repsTarget: "8",
                  currentWeightKg: 50, progressionStepKg: 2.5, weekday: 0, sessionId: 7)]
    }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut {
        throw HubError.http(status: 404, detail: "Plan session not found")
    }
}

// MARK: - Sheet text

@Test func sheetTextNeverShowsAZeroForSomethingMissing() {
    #expect(trainingDaySheetTitle(weekday: 2, date: "2026-09-30") == "Wednesday · 30 Sep")
    #expect(trainingDaySheetTitle(weekday: 2, date: "") == "Wednesday")
    #expect(trainingLiftLine(lift(1, "A", weekday: nil, sessionId: nil)) == "3 × 8 · 50 kg")
    let bare = Exercise(exerciseId: 2, sessionName: "A", exerciseName: "Plank", sets: nil, repsTarget: nil,
                        currentWeightKg: 0, progressionStepKg: nil, weekday: nil, sessionId: nil)
    #expect(trainingLiftLine(bare) == nil)
    #expect(trainingDayEntrySubtitle(.strength(id: 1, name: "A", lifts: [])) == "Strength")
    #expect(trainingDayEntrySubtitle(.scheduled(name: "Long Z2", kind: .longRun)) == "Long run · follows the morning-call schedule")
    #expect(trainingDayEntrySubtitle(.session(id: 6, name: "Long Zone 2", kind: .longRun)) == "Long run · in your plan")
    #expect(trainingDayEntrySubtitle(.session(id: 7, name: "Rest", kind: .rest)) == "Rest · in your plan")
    let o = trainingDayOptions(weekday: 2, spine: spine, templates: library)
    #expect(trainingDayOptionSubtitle(o.library[0]) == "On Wed, Fri")
    #expect(trainingDayOptionSubtitle(o.plan[2]) == "Not on a day")
}

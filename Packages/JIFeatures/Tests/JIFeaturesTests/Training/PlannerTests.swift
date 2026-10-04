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

// MARK: - PL-4: the Planner's filters and rows

@Test func strengthFilterListsTheFourDaySessions() {
    let rows = plannerFiltered(plannerHubRows(), .strength, templates: plannerLibrary)
    #expect(rows.map(\.name) == ["Day 1 Full Upper", "Day 2 Full Upper", "Day 3 Full Upper", "Day 4 Full Upper"])
}

@Test func strengthFilterAlsoListsATemplateWithAStrengthSegment() {
    var mixed = plannerTemplate("Gym + Run", id: 9, weekdays: [3])
    mixed.segments.append(WorkoutSegment(sport: .strength, steps: []))
    var hub = plannerHubRows()
    hub.append(PlannerWorkout(ref: "t9", kind: .template, name: "Gym + Run", sport: "running", weekdays: [3], editable: true))
    let rows = plannerFiltered(hub, .strength, templates: plannerLibrary + [mixed])
    #expect(rows.map(\.ref) == ["s1", "s2", "s3", "s4", "t9"])
}

@Test func notOnADayListsDay4AndRunListsTheCardio() {
    #expect(plannerFiltered(plannerHubRows(), .unassigned, templates: plannerLibrary).map(\.name) == ["Day 4 Full Upper"])
    let run = plannerFiltered(plannerHubRows(), .run, templates: plannerLibrary)
    #expect(run.map(\.ref) == ["s5", "s6", "s8", "t1", "t2", "t3", "t4"])
    #expect(plannerFiltered(plannerHubRows(), .all, templates: plannerLibrary).count == 11)
}

@Test func noFilterIsEverEmptyWithThisPlanAndNoneSaysNoneInThisFilter() {
    for f in PlannerFilter.allCases {
        #expect(!plannerFiltered(plannerHubRows(), f, templates: plannerLibrary).isEmpty, "\(f.rawValue) is empty")
        #expect(plannerEmptyText(f, hasAny: true) != "None in this filter.")
    }
    #expect(PlannerFilter.allCases.map(\.rawValue) == ["All", "Strength", "Run", "Not on a day"])
}

@Test func rowSubtitlesNameWhatAndWhen() {
    let rows = plannerHubRows()
    let day4 = rows.first { $0.ref == "s4" }!, day1 = rows.first { $0.ref == "s1" }!
    #expect(plannerRowSubtitle(day4, template: nil) == "6 lifts · Not on a day")
    #expect(plannerRowSubtitle(day1, template: nil) == "6 lifts · Mon")
    let z2 = rows.first { $0.ref == "t2" }!
    #expect(plannerRowSubtitle(z2, template: plannerLibrary[1]) == WorkoutFormat.summary(plannerLibrary[1]) + " · Mon")
    let n44 = rows.first { $0.ref == "t3" }!
    #expect(plannerRowSubtitle(n44, template: plannerLibrary[2]).hasSuffix(" · Tue, Sat"))
    #expect(plannerStatement == "Your week, and every workout you can put in it.")
}

@Test func strengthDetailListsTheSessionsLiftsWithTheNextWeight() {
    let ref = PlannerStrengthRef(plannerHubRows().first { $0.ref == "s4" }!)
    #expect(ref.weekdays.isEmpty && ref.sessionId == 4)
    let lifts = plannerStrengthLifts(ref, exercises: plannerExercises(), progressions: [])
    #expect(lifts.count == 6 && lifts.allSatisfy { $0.exerciseId.map { (40..<46).contains($0) } ?? false })
    #expect(plannerLiftLine(lifts[0]) == "Next 40 kg · 3 × 8")
}

// MARK: - PL-5: one way in, one list

private func plannerSource(_ relative: String) throws -> String {
    let pkg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try String(contentsOf: pkg.appending(path: "Sources/JIFeatures/\(relative)"), encoding: .utf8)
}

@Test func noStandaloneWorkoutLibraryScreenIsPushedAnyMore() throws {
    let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/JIFeatures")
    let files = FileManager.default.enumerator(at: src, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    #expect(files.count > 50)
    for f in files where f.lastPathComponent != "PlannerView.swift" {
        let body = try String(contentsOf: f, encoding: .utf8)
        #expect(!body.contains("WorkoutLibraryView("), "\(f.lastPathComponent) still pushes the standalone library")
    }
}

@Test @MainActor func theDaySheetHasNoLibraryRoute() throws {
    #expect(TrainingDaySheet.Route.pick(replacing: nil) == .pick(replacing: nil))
    let sheet = try plannerSource("Training/TrainingDaySheet.swift")
    #expect(!sheet.contains("case library"))
    #expect(!sheet.contains(".library)"))
    #expect(TrainingView.launchArgumentDayRoute(["app", "-training-day-route", "library"]) == nil)
}

@Test func trainingTodayAndTheToolbarAllOpenThePlanner() throws {
    let training = try plannerSource("Training/TrainingView.swift")
    // Verifier PL-5: both ways in hand the Planner the set logger + Watch sender (a pushed
    // destination does not inherit the presenter's environment).
    #expect(training.contains("navigationDestination(isPresented: $showWeek) { PlannerView(model: model, strengthLogDeps: strengthLogDeps, sendWatchPlan: sendWatchPlan) }"))
    #expect(training.contains("Button { showWeek = true } label: { Image(systemName: \"figure.run.square.stack\") }"))
    #expect(try plannerSource("Today/TodayView.swift").contains("PlannerView(model: weekModel, strengthLogDeps: strengthLogDeps, sendWatchPlan: sendWatchPlan)"))
}

/// Verifier PL-4/PL-5: Day 1's detail (a nested push) gets Log sets + Send to Watch — the Planner
/// re-injects both on its own push; the ALL WORKOUTS container keeps its rows' ids.
@Test func thePlannersStrengthDetailIsHandedItsLogAndWatchDeps() throws {
    let planner = try plannerSource("Training/PlannerView.swift")
    #expect(planner.contains(".environment(\\.strengthLogDeps, strengthLogDepsIn ?? envStrengthLogDeps)"))
    #expect(planner.contains(".environment(\\.strengthWatchPlanSender, sendWatchPlanIn ?? envSendWatchPlan)"))
    #expect(planner.contains(".accessibilityElement(children: .contain)\n            .accessibilityIdentifier(\"workouts-list\")"))
}

@Test func thePickerListsThePlannersRowsInTheSameOrder() {
    let spine = trainingDaySpine(strength: weekSpine(planSessions: Array(plannerSessions.prefix(4)), exercises: plannerExercises()), sessions: plannerSessions)
    let rows = plannerHubRows()
    let options = plannerDayOptions(weekday: 6, rows: rows, spine: spine, templates: plannerLibrary)
    #expect(options.map(\.id) == rows.map(\.ref))
    #expect(options.first { $0.id == "s4" }?.choice == .planSession(id: 4, name: "Day 4 Full Upper"))
    #expect(options.first { $0.id == "s4" }?.currentDays == [])
    #expect(options.first { $0.id == "t1" }?.isOnThisDay == true)
    #expect(options.first { $0.id == "s5" }?.kind == .interval)
    // A template the library has not loaded is not offered (nothing to write it with).
    #expect(plannerDayOptions(weekday: 6, rows: rows, spine: spine, templates: []).count == 7)
}

@Test @MainActor func pickingFromTheUnifiedPickerWritesThroughChangeDay() async throws {
    let hub = PlannerHub()
    let vm = makePlannerVM(hub, cache: OfflineCache(db: try AppDatabase.inMemory()), outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()
    let day4 = try #require(vm.plannerOptions(weekday: 6).first { $0.id == "s4" })
    #expect(await vm.changeDay(weekday: 6, adding: day4.choice, removing: nil) == .saved)
    #expect(hub.weekdayCalls.count == 1 && hub.weekdayCalls[0].0 == 4 && hub.weekdayCalls[0].1 == 6)
    #expect(vm.plannerWorkouts.first { $0.ref == "s4" }?.weekdays == [6])
}

// MARK: - PL-6: the hero names the whole day

private func mondayPreview() -> TrainingDayPreview {
    let spine = trainingDaySpine(strength: weekSpine(planSessions: Array(plannerSessions.prefix(4)), exercises: plannerExercises()), sessions: plannerSessions)
    let mon = TrainingWeekDay(weekday: 0, date: "2026-10-05", kind: .strength, sessionName: "Day 1 Full Upper", sessionId: 1, done: nil, isToday: true)
    return trainingDayPreview(day: mon, spine: spine, exercises: plannerExercises(), templates: plannerLibrary)
}

@Test func heroTitleNamesTheStrengthSessionAndTheDaysRun() {
    let p = mondayPreview()
    #expect(trainingHeroTitle(day: p) == "Day 1 Full Upper + Zone 2 40 min")
    // The hub's planned session leads and is never named twice.
    #expect(trainingHeroTitle(day: p, sessionName: "Day 1 Full Upper") == "Day 1 Full Upper + Zone 2 40 min")
    #expect(trainingHeroTitle(day: p, sessionName: "day 1  full upper") == "day 1  full upper + Zone 2 40 min")
    // Nothing known → nil (the hero says "— No data", never an invented name).
    #expect(trainingHeroTitle(day: nil, sessionName: nil) == nil)
    #expect(trainingHeroTitle(day: nil, sessionName: "Day 2 Full Upper") == "Day 2 Full Upper")
    let rest = TrainingDayPreview(weekday: 6, date: "2026-10-11", isToday: false, entries: [])
    #expect(trainingHeroTitle(day: rest) == nil)
}

@Test func sendToWatchPreselectsTheDaysTemplate() {
    #expect(trainingHeroTemplateId(day: mondayPreview()) == 2)
    #expect(trainingHeroTemplateId(day: TrainingDayPreview(weekday: 6, date: "", isToday: false, entries: [])) == nil)
    #expect(trainingHeroTemplateId(day: nil) == nil)
}

// MARK: - PL-7: drag a workout onto a day = assign; between days = move

private func plannerSpine() -> [WeekSpineEntry] {
    trainingDaySpine(strength: weekSpine(planSessions: Array(plannerSessions.prefix(4)), exercises: plannerExercises()), sessions: plannerSessions)
}

@Test func dragPayloadRoundTrips() {
    #expect(PlannerDragItem(ref: "t1").payload == "planner|t1")
    #expect(PlannerDragItem(ref: "s1", fromWeekday: 0).payload == "planner|s1|0")
    #expect(PlannerDragItem(payload: "planner|s1|0") == PlannerDragItem(ref: "s1", fromWeekday: 0))
    #expect(PlannerDragItem(payload: "planner|t12") == PlannerDragItem(ref: "t12"))
    #expect(PlannerDragItem(payload: "hello") == nil)
    #expect(PlannerDragItem(payload: "planner|x1") == nil)
    #expect(PlannerDragItem(payload: "planner|t1|9") == nil)
}

@Test func droppingAnUnassignedTemplateOnTheEmptySundayAssignsIt() {
    var lib = plannerLibrary
    lib[0].weekdays = []   // PL-10: Long Run Zone 2 stays in ALL WORKOUTS, on no day
    #expect(plannerDropWrites(PlannerDragItem(ref: "t1"), toWeekday: 6, spine: plannerSpine(), templates: lib)
            == [.templateWeekdays(lib[0], [6])])
}

@Test func droppingASessionFromAllWorkoutsOrFromADayMovesItsOneWeekday() {
    #expect(plannerDropWrites(PlannerDragItem(ref: "s4"), toWeekday: 6, spine: plannerSpine(), templates: plannerLibrary)
            == [.sessionWeekday(id: 4, name: "Day 4 Full Upper", weekday: 6)])
    #expect(plannerDropWrites(PlannerDragItem(ref: "s1", fromWeekday: 0), toWeekday: 6, spine: plannerSpine(), templates: plannerLibrary)
            == [.sessionWeekday(id: 1, name: "Day 1 Full Upper", weekday: 6)])
}

@Test func draggingATemplateBetweenDaysMovesThatDayOnly() {
    // Norwegian 4×4 is on Tue + Sat; dragged from Tue to Sun → Sat + Sun.
    #expect(plannerDropWrites(PlannerDragItem(ref: "t3", fromWeekday: 1), toWeekday: 6, spine: plannerSpine(), templates: plannerLibrary)
            == [.templateWeekdays(plannerLibrary[2], [5, 6])])
    // From ALL WORKOUTS it is added (both days stay).
    #expect(plannerDropWrites(PlannerDragItem(ref: "t3"), toWeekday: 6, spine: plannerSpine(), templates: plannerLibrary)
            == [.templateWeekdays(plannerLibrary[2], [1, 5, 6])])
}

@Test func droppingWhereItAlreadyIsWritesNothing() {
    #expect(plannerDropWrites(PlannerDragItem(ref: "s1", fromWeekday: 0), toWeekday: 0, spine: plannerSpine(), templates: plannerLibrary).isEmpty)
    #expect(plannerDropWrites(PlannerDragItem(ref: "t2"), toWeekday: 0, spine: plannerSpine(), templates: plannerLibrary).isEmpty)
    #expect(plannerDropWrites(PlannerDragItem(ref: "t3", fromWeekday: 1), toWeekday: 1, spine: plannerSpine(), templates: plannerLibrary).isEmpty)
    // Unknown rows (not in the plan / library) write nothing.
    #expect(plannerDropWrites(PlannerDragItem(ref: "s99"), toWeekday: 0, spine: plannerSpine(), templates: plannerLibrary).isEmpty)
    #expect(plannerDropWrites(PlannerDragItem(ref: "t99"), toWeekday: 0, spine: plannerSpine(), templates: plannerLibrary).isEmpty)
}

@Test @MainActor func droppingLongRunOnSundayWritesTheTemplateAndShowsAtOnce() async throws {
    var lib = plannerLibrary
    lib[0].weekdays = []
    let hub = PlannerHub(templates: lib)
    let vm = makePlannerVM(hub, cache: OfflineCache(db: try AppDatabase.inMemory()), outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()
    #expect(vm.dayPreview(weekday: 6).entries.allSatisfy { $0.title != "Long Run Zone 2" })

    let result = await vm.drop(PlannerDragItem(ref: "t1").payload, onDay: 6)

    #expect(result == .saved)
    #expect(hub.workouts.writes == ["PUT 1"])
    #expect(hub.workouts.lastDraft?.weekdays == [6])
    #expect(vm.dayPreview(weekday: 6).entries.map(\.title).contains("Long Run Zone 2"))
    #expect(vm.plannerWorkouts.first { $0.ref == "t1" }?.weekdays == [6])
}

@Test @MainActor func draggingASessionBetweenDaysOfflineQueuesTheSameWeekdayWrite() async throws {
    let hub = PlannerHub()
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let vm = makePlannerVM(hub, cache: OfflineCache(db: try AppDatabase.inMemory()), outbox: outbox)
    await vm.load()
    hub.offline = true

    let result = await vm.drop(PlannerDragItem(ref: "s1", fromWeekday: 0).payload, onDay: 6)

    #expect(result == .queued)
    #expect(hub.weekdayCalls.isEmpty)
    #expect(try outbox.pending().count == 1)
    #expect(vm.dayPreview(weekday: 6).entries.map(\.title).contains("Day 1 Full Upper"))
    #expect(!vm.dayPreview(weekday: 0).entries.map(\.title).contains("Day 1 Full Upper"))
}

@Test @MainActor func aForeignPayloadIsRefusedWithoutAWrite() async throws {
    let hub = PlannerHub()
    let vm = makePlannerVM(hub, cache: OfflineCache(db: try AppDatabase.inMemory()), outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()
    if case .refused = await vm.drop("https://example.com", onDay: 6) {} else { Issue.record("a foreign drop must be refused") }
    #expect(hub.weekdayCalls.isEmpty && hub.workouts.writes.isEmpty)
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// B-52 (W-B41 L2): the weekday a plan session is trained on is an OFFLINE-FIRST write — queued in
// the `Outbox` before the hub is asked, never rolled back because the hub was unreachable, and
// marked "pending sync" on screen until the drainer lands it.
// Toby, 2026-09-22: "nothing is more stupid than an app that doesn't work without internet."

/// A `TrainingProviding` that ALSO conforms to the narrow `PlanSessionWeekdayProviding` the
/// drainer replays `plan_weekday` rows with — i.e. the shape `HubDataProvider` has.
nonisolated final class PlanWeekdayFakeProvider: TrainingProviding, PlanSessionWeekdayProviding, @unchecked Sendable {
    var rows: [Exercise] = [
        Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: nil, sessionId: 7),
    ]
    /// nil = the hub takes the write. Non-nil = it throws this instead.
    var weekdayError: Error?
    /// true = every READ throws, i.e. the hub is not there at all.
    var readsFail = false
    var calls: [(Int, Int?)] = []

    func trainingDay(date: String) async throws -> TrainingDayDetail {
        if readsFail { throw HubError.network("offline") }
        return TrainingDayDetail(date: date, activities: [], exerciseSets: [])
    }
    func exercises() async throws -> [Exercise] {
        if readsFail { throw HubError.network("offline") }
        return rows
    }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        ExerciseUpdateResult(exerciseId: exerciseId, updated: true)
    }
    func updatePlanSessionWeekday(sessionId: Int, weekday: Int?) async throws -> PlanSessionOut {
        calls.append((sessionId, weekday))
        if let weekdayError { throw weekdayError }
        return PlanSessionOut(id: sessionId, name: "Day 1 Full Upper", weekday: weekday)
    }
}

@MainActor
private func makeVM(
    training: PlanWeekdayFakeProvider,
    cache: OfflineCache,
    outbox: Outbox?
) -> TrainingViewModel {
    TrainingViewModel(
        provider: training, healthProvider: MockDataProvider(), cache: cache,
        strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "b52.\(UUID().uuidString)")),
        outbox: outbox,
        drainer: outbox.map { OutboxDrainer(outbox: $0, weighIn: nil, gateRespond: nil, planWeekday: training) },
        now: { ISO8601DateFormatter().date(from: "2026-09-22T08:00:00Z")! }
    )
}

// MARK: - The drainer knows the new kind

@Test @MainActor func aQueuedPlanWeekdayRowIsDeliveredAndReportedAsSuch() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub)
    let id = try outbox.enqueue(
        kind: OutboxDrainer.planWeekdayKind,
        payload: PlanWeekdayBody(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)
    )

    let results = await drainer.drainOnce()

    guard case .success(.planWeekday(let session)) = results[id] else { Issue.record("expected planWeekday success"); return }
    #expect(session.id == 7)
    #expect(session.weekday == 3)
    #expect(hub.calls.count == 1)
    #expect(hub.calls[0].1 == 3)
    #expect(try outbox.pending().isEmpty)   // delivered rows are retired
}

@Test @MainActor func aPlanWeekdayRowStaysPendingWhenTheHubIsUnreachable() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.network("Could not connect to the server.")
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub)
    let id = try outbox.enqueue(
        kind: OutboxDrainer.planWeekdayKind,
        payload: PlanWeekdayBody(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)
    )

    _ = await drainer.drainOnce()

    let rows = try outbox.pending()
    #expect(rows.count == 1)
    #expect(rows[0].id == id)
    #expect(rows[0].attempts == 1)
    #expect(rows[0].lastError == "Could not connect to the server.")
}

@Test @MainActor func planWeekdayIsDrainableOnlyWhenAProviderCanDeliverIt() throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    #expect(OutboxDrainer.knownKinds.contains(OutboxDrainer.planWeekdayKind))
    #expect(OutboxDrainer.planWeekdayKind == "plan_weekday")
    let without = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil)
    #expect(!without.drainableKinds.contains(OutboxDrainer.planWeekdayKind))
    let with = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: PlanWeekdayFakeProvider())
    #expect(with.drainableKinds.contains(OutboxDrainer.planWeekdayKind))
}

@Test @MainActor func aRowOfTheNewKindIsLeftUntouchedByADrainerThatCannotDeliverIt() async throws {
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let drainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil)
    _ = try outbox.enqueue(kind: OutboxDrainer.planWeekdayKind, payload: PlanWeekdayBody(sessionId: 7, sessionName: "Day 1", weekday: 0))

    let results = await drainer.drainOnce()

    #expect(results.isEmpty)
    #expect(try outbox.pending().count == 1)      // never silently dropped
    #expect(try outbox.pending()[0].attempts == 0) // and never even attempted
}

// MARK: - assignSession is outbox-first

@Test @MainActor func anOfflineAssignmentStandsIsQueuedAndIsMarkedPending() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.network("offline")
    let vm = makeVM(training: hub, cache: cache, outbox: outbox)
    await vm.load()

    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)

    // The tap stands on screen — no rollback, no "couldn't save" lie.
    #expect(vm.exercises.first?.weekday == 3)
    #expect(vm.sessionAssignFailed.isEmpty)
    // …it is durably queued…
    let rows = try outbox.pending()
    #expect(rows.count == 1)
    #expect(rows[0].kind == OutboxDrainer.planWeekdayKind)
    let body = try JSONDecoder().decode(PlanWeekdayBody.self, from: rows[0].payload)
    #expect(body == PlanWeekdayBody(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3))
    // …said out loud as pending…
    #expect(vm.pendingSessionSync.contains(7))
    #expect(vm.pendingSessionAssign.isEmpty)
    // …and survives a relaunch, because the optimistic rows were persisted.
    let cachedExercises = try cache.get("training.exercises", as: [Exercise].self)
    #expect(cachedExercises?.value.first?.weekday == 3)
    let cachedSessions = try cache.get("training.planSessions", as: [PlanSessionOut].self)
    #expect(cachedSessions?.value.first(where: { $0.id == 7 })?.weekday == 3)
}

@Test @MainActor func aQueuedAssignmentClearsItsMarkerOnceTheHubTakesIt() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.network("offline")
    let vm = makeVM(training: hub, cache: cache, outbox: outbox)
    await vm.load()
    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)
    #expect(vm.pendingSessionSync.contains(7))

    // The hub comes back and somebody else drains (watchdog / retry scheduler): the marker is
    // recomputed from the queue, so this screen needs no wiring to that drainer.
    hub.weekdayError = nil
    let foreignDrainer = OutboxDrainer(outbox: outbox, weighIn: nil, gateRespond: nil, planWeekday: hub)
    _ = await foreignDrainer.drainOnForeground()
    vm.reconcilePendingSync()

    #expect(vm.pendingSessionSync.isEmpty)
    #expect(vm.exercises.first?.weekday == 3)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func areachableHubTakesTheRowInTheSameTapAndLeavesNoMarker() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    let vm = makeVM(training: hub, cache: cache, outbox: outbox)
    await vm.load()

    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)

    #expect(vm.exercises.first?.weekday == 3)
    #expect(vm.pendingSessionSync.isEmpty)
    #expect(vm.sessionAssignFailed.isEmpty)
    #expect(try outbox.pending().isEmpty)
}

@Test @MainActor func aHubThatRefusesTheRowRollsBackAndSaysSoRatherThanRetryingForever() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.http(status: 404, detail: "no such plan session")
    let vm = makeVM(training: hub, cache: cache, outbox: outbox)
    await vm.load()

    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)

    #expect(vm.sessionAssignFailed.contains(7))
    #expect(vm.pendingSessionSync.isEmpty)
    #expect(vm.exercises.first?.weekday == nil)   // a refusal IS the hub's truth
    #expect(try outbox.pending().isEmpty)         // and the row is retired, not retried forever
}

@Test @MainActor func a5xxIsTreatedAsUnreachableNotAsARefusal() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.http(status: 503, detail: "hub restarting")
    let vm = makeVM(training: hub, cache: cache, outbox: outbox)
    await vm.load()

    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)

    #expect(vm.pendingSessionSync.contains(7))
    #expect(vm.sessionAssignFailed.isEmpty)
    #expect(vm.exercises.first?.weekday == 3)
    #expect(try outbox.pending().count == 1)
}

// MARK: - The offline read

@Test @MainActor func planSessionsComeBackFromTheCacheOnAColdOfflineLaunch() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    // Seed the cache the way a previous online session would have.
    try cache.put("training.exercises", hub.rows)
    try cache.put("training.planSessions", [PlanSessionOut(id: 7, name: "Day 1 Full Upper", weekday: 5)])

    // …now the hub is gone entirely: every read throws, so only the cache can answer.
    let offlineHub = PlanWeekdayFakeProvider()
    offlineHub.readsFail = true
    let vm = makeVM(training: offlineHub, cache: cache, outbox: outbox)
    await vm.load()

    #expect(vm.exercises.count == 1)
    #expect(vm.planSessions == [PlanSessionOut(id: 7, name: "Day 1 Full Upper", weekday: 5)])
    _ = hub
}

@Test @MainActor func aSuccessfulFetchDerivesAndCachesThePlanSessionSpine() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.rows = [
        Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 2, sessionId: 7),
        Exercise(exerciseId: 2, sessionName: "Day 1 Full Upper", exerciseName: "Row", sets: 3,
                 repsTarget: "8", currentWeightKg: 40, progressionStepKg: 2.5, weekday: 2, sessionId: 7),
        Exercise(exerciseId: 3, sessionName: "Day 2 Full Upper", exerciseName: "Press", sets: 3,
                 repsTarget: "8", currentWeightKg: 30, progressionStepKg: 2.5, weekday: nil, sessionId: 8),
    ]
    let vm = makeVM(training: hub, cache: cache, outbox: Outbox(db: try AppDatabase.inMemory()))
    await vm.load()

    #expect(vm.planSessions == [
        PlanSessionOut(id: 7, name: "Day 1 Full Upper", weekday: 2),
        PlanSessionOut(id: 8, name: "Day 2 Full Upper", weekday: nil),
    ])
    let cached = try cache.get("training.planSessions", as: [PlanSessionOut].self)
    #expect(cached?.value.count == 2)
}

@Test @MainActor func arefreshDoesNotUndoAWeekdayStillWaitingToSync() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.weekdayError = HubError.network("offline")
    let vm = makeVM(training: hub, cache: cache, outbox: outbox)
    await vm.load()
    await vm.assignSession(sessionId: 7, sessionName: "Day 1 Full Upper", weekday: 3)

    // The hub's plan list still says "not assigned" — it hasn't been told yet.
    await vm.refresh()

    #expect(vm.pendingSessionSync.contains(7))
    #expect(vm.planSessions.first(where: { $0.id == 7 })?.weekday == 3)
    #expect(vm.exercises.first?.weekday == 3)
}

// MARK: - What the week strip row stands for

@Test func theCachedSpineOutranksTheExerciseRowsForBothIdAndWeekday() {
    let rows = [
        Exercise(exerciseId: 19, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 0, sessionId: nil),
    ]
    // A hub that withholds `session_id` leaves the row with NO assignable id. It must never fall
    // back to the `exercise_id` (19): `PUT /planning/plan-sessions/19` 404s, so the tap would
    // queue a write the hub can only refuse.
    let bare = weekStripSession(named: "Day 1 Full Upper", exercises: rows, planSessions: [])
    #expect(bare.id == nil)
    #expect(bare.weekday == 0)

    // With the spine (real id 1, and a weekday queued offline) both come from it.
    let spined = weekStripSession(
        named: "Day 1 Full Upper", exercises: rows,
        planSessions: [PlanSessionOut(id: 1, name: "Day 1 Full Upper", weekday: 3)]
    )
    #expect(spined.id == 1)
    #expect(spined.weekday == 3)
}

/// The blocking B-52 defect: the id the assign sheet PUTs must be a `plan.plan_session` id, never
/// an `exercise_id`. With the hub serving `session_id` (it now does — `GET /planning/exercises`
/// selects `se.session_id`), the spine carries it and the row is assignable; withheld, the row
/// offers no id at all rather than one the PUT route 404s on.
@Test @MainActor func theStripAssignsWithTheHubsRealPlanSessionIdAndNeverTheExerciseId() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.rows = [
        Exercise(exerciseId: 19, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 0, sessionId: 1),
        Exercise(exerciseId: 25, sessionName: "Day 2 Full Upper", exerciseName: "Row", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 2, sessionId: 2),
    ]
    let vm = makeVM(training: hub, cache: cache, outbox: nil)
    await vm.load()

    #expect(vm.planSessions.map(\.id) == [1, 2])
    #expect(!vm.planSessions.map(\.id).contains(19))
    #expect(weekStripSession(named: "Day 1 Full Upper", exercises: vm.exercises, planSessions: vm.planSessions).id == 1)
    #expect(weekStripSession(named: "Day 2 Full Upper", exercises: vm.exercises, planSessions: vm.planSessions).id == 2)

    // …and a hub that withholds it contributes no spine row, so nothing fabricates id 19.
    let cache2 = OfflineCache(db: try AppDatabase.inMemory())
    let old = PlanWeekdayFakeProvider()
    old.rows = hub.rows.map { row in
        var r = row; r.sessionId = nil; return r
    }
    let vm2 = makeVM(training: old, cache: cache2, outbox: nil)
    await vm2.load()
    #expect(vm2.planSessions.isEmpty)
    #expect(weekStripSession(named: "Day 1 Full Upper", exercises: vm2.exercises, planSessions: vm2.planSessions).id == nil)
}

@Test @MainActor func anOfflineAssignmentMakesTheStripRowPointAtTheRealSessionId() async throws {
    let cache = OfflineCache(db: try AppDatabase.inMemory())
    let outbox = Outbox(db: try AppDatabase.inMemory())
    let hub = PlanWeekdayFakeProvider()
    hub.rows = [
        Exercise(exerciseId: 19, sessionName: "Day 1 Full Upper", exerciseName: "Bench", sets: 3,
                 repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 0, sessionId: nil),
    ]
    hub.weekdayError = HubError.network("offline")
    let vm = makeVM(training: hub, cache: cache, outbox: outbox)
    await vm.load()
    #expect(weekStripSession(named: "Day 1 Full Upper", exercises: vm.exercises, planSessions: vm.planSessions).id == nil)

    // Assigned with the REAL plan-session id (the day detail's `planned_session`): the spine row
    // is corrected in place, not duplicated, so the marker and the next PUT use id 1.
    await vm.assignSession(sessionId: 1, sessionName: "Day 1 Full Upper", weekday: 3)
    #expect(vm.planSessions.filter { $0.name == "Day 1 Full Upper" }.count == 1)
    let resolved = weekStripSession(named: "Day 1 Full Upper", exercises: vm.exercises, planSessions: vm.planSessions)
    #expect(resolved.id == 1)
    #expect(resolved.weekday == 3)
    #expect(resolved.id.map { vm.pendingSessionSync.contains($0) } == true)
}

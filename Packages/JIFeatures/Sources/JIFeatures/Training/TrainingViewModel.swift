import Foundation
import Observation
import JICore
import JIPersistence

/// Training screen view model (W3a-L3). Mirrors `TodayViewModel`'s phase discipline (CODE-1 /
/// PARITY-7) over three independently-loadable primary sections (`gate`, `morning`, `exercises`)
/// plus a fourth, date-scoped section (`dayDetail`) that never blocks the overall `phase` — the
/// oracle's day-strip tap-through (`useTrainingDay`) re-queries per selected date with its own
/// loading flag, exactly like `TrainingDayDetailCard`'s RN counterpart.
///
/// Two provider dependencies, unlike the single-provider Recovery/Today pattern: `healthProvider`
/// supplies the frozen, already-existing `gate`/`morning` slice (consume-only per the Data seam);
/// `provider` is this lane's own new `TrainingProviding` slice (day detail / exercises / PATCH).
@Observable @MainActor
public final class TrainingViewModel {
    public enum Phase: Equatable, Sendable { case idle, loading, loaded, empty, error(String) }

    public private(set) var phase: Phase = .idle
    public private(set) var gate: GateResponse?
    public private(set) var morning: MorningResponse?
    public private(set) var exercises: [Exercise] = []
    public private(set) var fetchedAt: Date?
    public private(set) var hubReachable = true
    public private(set) var hasLiveResult = false
    public private(set) var lastError: HubError?

    public private(set) var selectedDate: String
    public private(set) var dayDetail: TrainingDayDetail?
    public private(set) var dayDetailLoading = false

    private let provider: any TrainingProviding
    private let healthProvider: any HealthDataProvider
    private let cache: OfflineCache
    private let strengthStore: StrengthStateStore
    private let now: () -> Date
    /// B-52: the durable write queue a weekday assignment is written to BEFORE the hub is asked,
    /// and the drainer that replays it. Optional so previews and the fixture-backed screen sweep
    /// keep working; when it is absent `assignSession` falls back to the direct PUT — still
    /// without a rollback, because the optimistic row is persisted either way.
    private let outbox: Outbox?
    private let drainer: OutboxDrainer?
    private static let keys = (
        gate: "training.gate", morning: "training.morning", exercises: "training.exercises",
        planSessions: "training.planSessions"
    )
    private var everSynced = false
    private var neverSyncedObserved = false
    private var dayDetailTask: Task<Void, Never>?

    /// Per-exercise "arm the reversal confirm / show a save failure" UI state — keyed by
    /// `exerciseId`, read by `LiftSteppers`. Kept on the VM (not local `@State` in the view) so a
    /// failed PATCH's error banner survives a view re-render.
    public private(set) var updateFailed: Set<Int> = []
    public private(set) var pendingUpdates: Set<Int> = []

    /// B-45 (c): plan-session ids with a weekday write in flight, and the ids whose last write
    /// failed — the assign sheet reads both so a failed PUT is said out loud, never swallowed.
    public private(set) var pendingSessionAssign: Set<Int> = []
    public private(set) var sessionAssignFailed: Set<Int> = []

    /// B-52: plan-session ids whose weekday is queued in the `Outbox` and NOT yet accepted by the
    /// hub. This is the honest replacement for B-45's rollback: the assignment stands on screen
    /// (it is durably queued, it will go out), and every surface that shows the session carries a
    /// "pending sync" marker until the drainer reports the row delivered.
    public private(set) var pendingSessionSync: Set<Int> = []

    /// B-52: the plan sessions (id / name / weekday) this screen knows about, cached alongside
    /// gate / morning / exercises so the week strip renders from disk on a cold, offline launch.
    /// Derived from the exercise rows on every successful fetch and updated optimistically by
    /// `assignSession` — it is the id-and-weekday spine the week strip reads, while the exercise
    /// rows stay the source for which lifts a session contains.
    public private(set) var planSessions: [PlanSessionOut] = []

    /// B-45 (a): the REAL device day this screen is being looked at on — never the hub's
    /// `verdict_date`, which is whatever day `scripts/morning_go.py` last wrote a verdict on.
    public var todayDate: Date { now() }

    /// B-45 (d): true when the hub says its verdict is stale, or (old hub, `isStale` absent) when
    /// the verdict's own date is not today. The screen then stops presenting the verdict's
    /// session as "today's".
    public var verdictIsStale: Bool {
        if let flag = morning?.isStale { return flag }
        guard let verdictDate = morning?.verdictDate else { return false }
        return verdictDate < todayDateString
    }

    /// The session planned for the SELECTED day. The hub's `planned_session` on the day detail is
    /// the source of truth (it joins `plan_session.weekday` server-side); a hub without the field
    /// falls back to the weekday carried on the plan rows themselves, and only then to nothing.
    public var plannedSessionForSelectedDay: PlannedSession? {
        if let planned = dayDetail?.plannedSession, dayDetail?.date == selectedDate { return planned }
        guard let weekday = selectedPlanWeekday else { return nil }
        guard let row = exercises.first(where: { $0.weekday == weekday }) else { return nil }
        return PlannedSession(id: row.sessionId ?? row.exerciseId, name: row.sessionName, weekday: weekday)
    }

    /// Mon = 0 … Sun = 6 for `selectedDate`, computed in the same UTC calendar the day keys use.
    public var selectedPlanWeekday: Int? {
        guard let date = trainingStripDate(selectedDate) else { return nil }
        return planWeekday(fromCalendarWeekday: trainingStripCalendar.component(.weekday, from: date))
    }

    public init(
        provider: any TrainingProviding,
        healthProvider: any HealthDataProvider,
        cache: OfflineCache,
        strengthStore: StrengthStateStore = StrengthStateStore(),
        selectedDate: String? = nil,
        outbox: Outbox? = nil,
        drainer: OutboxDrainer? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider; self.healthProvider = healthProvider; self.cache = cache
        self.strengthStore = strengthStore; self.now = now
        self.outbox = outbox; self.drainer = drainer
        self.selectedDate = selectedDate ?? String(now().ISO8601Format().prefix(10))
    }

    public var screenState: ScreenState {
        ScreenState.resolve(phase: mappedPhase, neverSynced: neverSyncedObserved, verdictDate: morning?.verdictDate, todayDateString: todayDateString, lastError: lastError)
    }

    private var mappedPhase: TodayViewModel.Phase {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .loaded: .loaded
        case .empty: .empty
        case .error(let message): .error(message)
        }
    }

    public var todayDateString: String { String(now().ISO8601Format().prefix(10)) }

    public func load() async {
        phase = .loading
        restoreFromCache()
        reconcilePendingSync()
        await fetchLive()
        loadDay(for: selectedDate)
    }

    public func refresh() async {
        reconcilePendingSync()
        await fetchLive()
        loadDay(for: selectedDate)
    }

    /// Day-strip tap-through (E15-10 in the oracle): re-queries `dayDetail` for the tapped date
    /// without touching `phase` — a stale/failed day detail never blanks the week strip or gate
    /// card above it.
    public func selectDate(_ date: String) {
        guard date != selectedDate else { return }
        selectedDate = date
        loadDay(for: date)
    }

    private func restoreFromCache() {
        if let g = try? cache.get(Self.keys.gate, as: GateResponse.self) { gate = g.value; fetchedAt = g.fetchedAt; everSynced = true }
        if let m = try? cache.get(Self.keys.morning, as: MorningResponse.self) { morning = m.value }
        if let e = try? cache.get(Self.keys.exercises, as: [Exercise].self) { exercises = e.value }
        // B-52: the week strip's id/weekday spine comes back with the rest of the cached set, so a
        // cold launch with no hub still shows which session is trained on which day — including a
        // weekday assigned while offline and still sitting in the outbox.
        if let p = try? cache.get(Self.keys.planSessions, as: [PlanSessionOut].self) { planSessions = p.value }
        if gate != nil { phase = .loaded }
        if gate != nil || morning != nil || !exercises.isEmpty { }
    }

    private func fetchLive() async {
        let hadEverSynced = everSynced
        let provider = self.healthProvider
        let trainingProvider = self.provider
        let cache = self.cache
        async let gR = SectionLoader.load(key: Self.keys.gate, cache: cache) { try await provider.gate(windowDays: 28) }
        async let mR = SectionLoader.load(key: Self.keys.morning, cache: cache) { try await provider.morning() }
        async let eR = SectionLoader.load(key: Self.keys.exercises, cache: cache) { try await trainingProvider.exercises() }
        let (g, m, e): (SectionResult<GateResponse>, SectionResult<MorningResponse>, SectionResult<[Exercise]>)
        do {
            (g, m, e) = try await (gR, mR, eR)
        } catch {
            if Task.isCancelled { if phase == .loading { phase = .idle }; return }
            lastError = (error as? HubError) ?? .decoding("\(error)")
            hubReachable = true
            phase = gate == nil ? .error(Self.describe(error)) : .loaded
            return
        }

        if let gv = g.value { gate = gv }
        if let mv = m.value { morning = mv }
        if let ev = e.value {
            exercises = ev
            // B-52: re-derive the plan-session spine ONLY from a section that actually came from
            // the hub. `SectionLoader` hands back the cached rows when the fetch failed, and those
            // rows are exactly the ones whose `weekday` may be older than what this device knows —
            // deriving from them would quietly undo an offline assignment on every failed refresh.
            if e.error == nil {
                let local = planSessions
                planSessions = Self.mergePendingWeekdays(into: derivePlanSessions(from: ev), pending: pendingSessionSync, previous: local)
                // …and the exercise rows too: a fetch that lands while a weekday is still queued
                // must not silently undo it on screen.
                for id in pendingSessionSync {
                    guard let kept = planSessions.first(where: { $0.id == id }) else { continue }
                    applyAssignment(sessionId: kept.id, sessionName: kept.name, weekday: kept.weekday)
                }
                persistPlan()
            } else if planSessions.isEmpty {
                // An older cache written before this key existed: derive a spine so the week strip
                // still has ids to mark, without claiming it is the hub's latest word.
                planSessions = derivePlanSessions(from: ev)
            }
        }
        fetchedAt = g.fetchedAt ?? fetchedAt

        let sectionErrors = [g.error, m.error, e.error].compactMap { $0 }
        let representative = sectionErrors.first { if case .unauthorized = $0 { return true }; return false }
            ?? sectionErrors.first { if case .network = $0 { return true }; return false }
            ?? sectionErrors.first
        lastError = representative

        switch representative {
        case .some(.unauthorized):
            hubReachable = true
            phase = .error(Self.describe(representative!))
        case .some(.network):
            hubReachable = false
            phase = gate == nil ? .error(Self.describe(representative!)) : .loaded
        case .some(let err):
            hubReachable = true
            phase = gate == nil ? .error(Self.describe(err)) : .loaded
        case .none:
            hubReachable = true
            hasLiveResult = true
            everSynced = true
            let isEmpty = gate == nil && exercises.isEmpty
            neverSyncedObserved = isEmpty && !hadEverSynced
            phase = isEmpty ? .empty : .loaded
        }
    }

    /// Fire-and-forget, cancelling any in-flight fetch for a previous date first (mirrors
    /// `keepPreviousData` — the view keeps showing the last `dayDetail` while a new one loads).
    private func loadDay(for date: String) {
        dayDetailTask?.cancel()
        dayDetailLoading = true
        dayDetailTask = Task { [weak self] in
            guard let self else { return }
            let result = try? await SectionLoader.load(key: "training.day.\(date)", cache: self.cache) { try await self.provider.trainingDay(date: date) }
            guard !Task.isCancelled else { return }
            if let value = result?.value { self.dayDetail = value }
            self.dayDetailLoading = false
        }
    }

    /// Weight/reps stepper commit (LiftSteppers). Local-first: a `HubError.network` failure still
    /// mutates `exercises` in place (via `StrengthStateStore`) instead of losing the tap — mirrors
    /// `useExerciseActions.ts`'s optimistic-update + `updateExerciseLocalFirst` fallback pair.
    public func updateExercise(exerciseId: Int, exerciseName: String, patch: ExerciseUpdate) async {
        updateFailed.remove(exerciseId)
        pendingUpdates.insert(exerciseId)
        let previous = exercises
        applyOptimistic(exerciseId: exerciseId, patch: patch)
        do {
            _ = try await updateExerciseLocalFirst(
                store: strengthStore, exerciseId: exerciseId, exerciseName: exerciseName, patch: patch,
                hubUpdate: { [provider] id, p in try await provider.updateExercise(exerciseId: id, patch: p) }
            )
            try? cache.put(Self.keys.exercises, exercises)
        } catch {
            exercises = previous
            updateFailed.insert(exerciseId)
        }
        pendingUpdates.remove(exerciseId)
    }

    /// B-45 (c) / B-52: assign a plan session to a weekday (or clear it) — **outbox first**.
    ///
    /// The order is the whole point (Toby, 2026-09-22: "nothing is more stupid than an app that
    /// doesn't work without internet"). The row goes into the durable `Outbox` BEFORE the hub is
    /// asked, the optimistic mutation is persisted to the cache on BOTH paths, and an unreachable
    /// hub no longer rolls the screen back — the assignment stands, marked pending, and the
    /// drainer (in-tap here, or later via the watchdog / retry scheduler / next launch) delivers
    /// it. The one case that still reads as a failure is a hub that *refused* this row (4xx, or a
    /// hub with no such route): retrying that forever would be a lie dressed as patience, so the
    /// row is retired, the rows go back to the hub's truth, and it is said out loud.
    public func assignSession(sessionId: Int, sessionName: String, weekday: Int?) async {
        sessionAssignFailed.remove(sessionId)
        pendingSessionAssign.insert(sessionId)
        defer { pendingSessionAssign.remove(sessionId) }

        let previousExercises = exercises
        let previousSessions = planSessions
        applyAssignment(sessionId: sessionId, sessionName: sessionName, weekday: weekday)
        persistPlan()

        guard let outbox, let drainer else {
            // No queue wired (previews, fixtures): the direct PUT is all there is. Still no
            // rollback on an unreachable hub — the optimistic row is already persisted, and
            // losing the tap would be the worse lie of the two.
            do { _ = try await provider.updatePlanSessionWeekday(sessionId: sessionId, weekday: weekday) }
            catch {
                if isRefusal(error) { rollBack(to: previousExercises, previousSessions, sessionId: sessionId) }
                else { pendingSessionSync.insert(sessionId) }
            }
            return
        }

        guard let rowId = try? outbox.enqueue(
            kind: OutboxDrainer.planWeekdayKind,
            payload: PlanWeekdayBody(sessionId: sessionId, sessionName: sessionName, weekday: weekday)
        ) else {
            // The queue itself is unwritable (disk full, DB locked). That is a real failure to
            // record the intent, not an offline moment, and must not masquerade as pending.
            rollBack(to: previousExercises, previousSessions, sessionId: sessionId)
            return
        }
        pendingSessionSync.insert(sessionId)

        // Same beat as `WeighInViewModel.submit`: a reachable hub confirms while the sheet is
        // still up. An unreachable one leaves the row queued and the marker on.
        let results = await drainer.drainOnce()
        if case .failure(let error)? = results[rowId], isRefusal(error) {
            try? outbox.markSent(id: rowId)   // retire a row the hub will never accept
            rollBack(to: previousExercises, previousSessions, sessionId: sessionId)
        }
        reconcilePendingSync()
    }

    /// B-52: the pending markers ARE the outbox — a `"plan_weekday"` row still queued means "not
    /// yet accepted". Recomputing from the queue (rather than bookkeeping a set by hand) means a
    /// drain run by ANY other owner — `HubWatchdog.onReachableAgain`, `OutboxRetryScheduler`, a
    /// previous launch — clears the marker the next time this screen loads, with no cross-wiring
    /// between them.
    public func reconcilePendingSync() {
        guard let outbox else { return }
        guard let rows = try? outbox.pending() else { return }
        var ids = Set<Int>()
        for row in rows where row.kind == OutboxDrainer.planWeekdayKind {
            guard let body = try? JSONDecoder().decode(PlanWeekdayBody.self, from: row.payload) else { continue }
            ids.insert(body.sessionId)
        }
        pendingSessionSync = ids
    }

    /// The hub refused THIS row (4xx other than 401, or an old hub with no such route) — as
    /// opposed to being unreachable, which is what the outbox exists for.
    private func isRefusal(_ error: Error) -> Bool {
        OutboxDrainer.isPermanentRejection(error) || error is PlanSessionUpdateUnavailable
    }

    private func rollBack(to rows: [Exercise], _ sessions: [PlanSessionOut], sessionId: Int) {
        exercises = rows
        planSessions = sessions
        pendingSessionSync.remove(sessionId)
        sessionAssignFailed.insert(sessionId)
        persistPlan()
    }

    private func persistPlan() {
        try? cache.put(Self.keys.exercises, exercises)
        try? cache.put(Self.keys.planSessions, planSessions)
    }

    /// The optimistic mutation itself, over both the exercise rows (so the Plan list re-labels)
    /// and the plan-session spine (so the week strip and the cached set agree).
    private func applyAssignment(sessionId: Int, sessionName: String, weekday: Int?) {
        exercises = exercises.map { row in
            guard row.sessionId == sessionId || (row.sessionId == nil && row.sessionName == sessionName) else { return row }
            var updated = row
            updated.weekday = weekday
            return updated
        }
        // Match on id first, then on name. The name fallback matters against a hub whose
        // `/planning/exercises` rows carry no `session_id`: the session then has no spine row of
        // its own, and an assignment made with a real plan-session id learned elsewhere (the day
        // detail's `planned_session`) must attach to the existing name rather than add a second
        // row under it.
        if let index = planSessions.firstIndex(where: { $0.id == sessionId })
            ?? planSessions.firstIndex(where: { $0.name == sessionName }) {
            planSessions[index] = PlanSessionOut(id: sessionId, name: sessionName, weekday: weekday)
        } else {
            planSessions.append(PlanSessionOut(id: sessionId, name: sessionName, weekday: weekday))
        }
    }

    /// First-appearance-order plan sessions carried by a set of exercise rows. Only REAL
    /// `plan.plan_session` ids enter the spine: a row whose `session_id` the hub withheld (and for
    /// which no id is otherwise known) is left out entirely rather than standing in its
    /// `exercise_id`. That fudge is what made B-52 undeliverable — `PUT /planning/plan-sessions/
    /// {exercise_id}` 404s, the outbox row was then classed a permanent refusal, and the
    /// assignment was rolled back exactly as B-45 used to do.
    private func derivePlanSessions(from rows: [Exercise]) -> [PlanSessionOut] {
        var seen = Set<String>()
        var out: [PlanSessionOut] = []
        for row in rows where !seen.contains(row.sessionName) {
            seen.insert(row.sessionName)
            // A real plan-session id already known for this name (from the day detail, or from an
            // assignment) is kept when a re-fetch arrives without one, so re-deriving never throws
            // the good id away.
            guard let id = rows.first(where: { $0.sessionName == row.sessionName && $0.sessionId != nil })?.sessionId
                ?? planSessions.first(where: { $0.name == row.sessionName })?.id
            else { continue }
            let weekday = rows.first { $0.sessionName == row.sessionName && $0.weekday != nil }?.weekday
            out.append(PlanSessionOut(id: id, name: row.sessionName, weekday: weekday))
        }
        return out
    }

    /// Keeps the locally-queued weekday for any session still pending sync, so a refresh that
    /// re-reads the hub's (older) view does not silently undo what the user assigned offline.
    private static func mergePendingWeekdays(into fresh: [PlanSessionOut], pending: Set<Int>, previous: [PlanSessionOut]) -> [PlanSessionOut] {
        guard !pending.isEmpty else { return fresh }
        return fresh.map { session in
            guard pending.contains(session.id), let local = previous.first(where: { $0.id == session.id }) else { return session }
            var kept = session
            kept.weekday = local.weekday
            return kept
        }
    }

    private func applyOptimistic(exerciseId: Int, patch: ExerciseUpdate) {
        exercises = exercises.map { row in
            guard row.exerciseId == exerciseId else { return row }
            var updated = row
            updated.currentWeightKg = patch.currentWeightKg
            updated.progressionStepKg = patch.progressionStepKg
            if let sets = patch.sets { updated.sets = sets }
            if let reps = patch.repsTarget { updated.repsTarget = String(reps) }
            return updated
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error as? HubError {
        case .unauthorized: "Hub rejected the token — check Settings › Connection."
        case .network: "Hub unreachable — is the Mac awake and on the same network?"
        case .some(let e): "Hub error: \(e)"
        case .none: "Unexpected error: \(error.localizedDescription)"
        }
    }
}

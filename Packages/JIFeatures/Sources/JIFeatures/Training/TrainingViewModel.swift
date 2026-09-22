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
    private static let keys = (gate: "training.gate", morning: "training.morning", exercises: "training.exercises")
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
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider; self.healthProvider = healthProvider; self.cache = cache
        self.strengthStore = strengthStore; self.now = now
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
        await fetchLive()
        loadDay(for: selectedDate)
    }

    public func refresh() async {
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
        if let ev = e.value { exercises = ev }
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

    /// B-45 (c): assign a plan session to a weekday (or clear it). Optimistic on `exercises`
    /// so the Plan list re-labels immediately; a failure rolls the rows back AND records the id
    /// in `sessionAssignFailed` rather than leaving a lie on screen.
    public func assignSession(sessionId: Int, sessionName: String, weekday: Int?) async {
        sessionAssignFailed.remove(sessionId)
        pendingSessionAssign.insert(sessionId)
        let previous = exercises
        exercises = exercises.map { row in
            guard row.sessionId == sessionId || (row.sessionId == nil && row.sessionName == sessionName) else { return row }
            var updated = row
            updated.weekday = weekday
            return updated
        }
        do {
            _ = try await provider.updatePlanSessionWeekday(sessionId: sessionId, weekday: weekday)
            try? cache.put(Self.keys.exercises, exercises)
        } catch {
            exercises = previous
            sessionAssignFailed.insert(sessionId)
        }
        pendingSessionAssign.remove(sessionId)
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

import Foundation
import Observation
import JICompute

// W-B38-B B-4/B-5/B-6: the Watch set screen's model (the views live in
// `WatchApp/Sources/StrengthLog*.swift`; the model sits here so `swift test` runs it without a
// watch simulator). Exercise list → set entry (Crown weight in the exercise's step, reps, RPE)
// prefilled by `LastSetDefaults` (gap #29); log / edit / delete a set (gap #31); rest timer
// auto-starts after a logged set and timed sets count down on `SetTimer` (gap #28); HR vs the
// cap via `SessionCap` (175 bpm cap / no Zone 5 on every HR surface).

public enum StrengthLogHaptic: Sendable, Equatable { case restDone, timedDone }

@MainActor
@Observable
public final class StrengthLogViewModel {
    public static let defaultRestS = 90
    /// The hard cap every HR surface honours when the phone sent no limit (rule: 175 bpm).
    public static let fallbackLimitBpm = 175
    /// Crown step when the plan names none: the smallest microplate pair (1.25 kg).
    public static let fallbackStepKg = 1.25

    public let controller: StrengthWorkoutSessionController
    public let bridge: StrengthSessionWatchBridge

    public private(set) var sessionClientId: UUID?
    public private(set) var selected: StrengthWatchExercise?
    public private(set) var loggedSets: [StrengthBridgeSet] = []
    public private(set) var editingSetId: UUID?
    public private(set) var timer = SetTimer() {
        // B-43 P1: every countdown change re-plans the background rest/timed-set end alert.
        didSet { if timer != oldValue { restAlert?.sync(timer, exercise: selected?.name, now: clock()) } }
    }
    /// Recomputed on `tick()` so the view redraws each second.
    public private(set) var remainingSeconds: Int?

    public var entryWeightKg: Double?
    public var entryReps: Int?
    public var entryRpe: Double?
    public var entryDurationS: Int?

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let haptic: (StrengthLogHaptic) -> Void
    /// B-43 P1: the local notification at the countdown's end (nil in tests that don't check it).
    @ObservationIgnored public let restAlert: RestEndAlert?
    @ObservationIgnored private var timedSetSeconds: Int?
    @ObservationIgnored private var timedSetStartedAt: Date?
    @ObservationIgnored var lastLiveSend: Task<Void, Never>?

    public init(controller: StrengthWorkoutSessionController, bridge: StrengthSessionWatchBridge,
                clock: @escaping () -> Date = { .now }, haptic: @escaping (StrengthLogHaptic) -> Void = { _ in },
                restAlert: RestEndAlert? = nil) {
        self.controller = controller
        self.bridge = bridge
        self.clock = clock
        self.haptic = haptic
        self.restAlert = restAlert
        controller.onHeartRate = { [weak self] bpm in
            guard let self else { return }
            let at = self.controller.heartRateAt ?? self.clock()
            self.lastLiveSend = Task { await self.bridge.send(.heartRate(bpm: bpm, at: at)) }
        }
    }

    // MARK: plan / HR

    public var exercises: [StrengthWatchExercise] { bridge.plan?.exercises ?? [] }

    public var limitBpm: Int { bridge.plan?.hrLimitBpm ?? Self.fallbackLimitBpm }

    public var capState: SessionCap.State {
        SessionCap.state(hrBpm: controller.heartRateBpm, limitBpm: limitBpm)
    }

    public func sets(for exercise: StrengthWatchExercise) -> [StrengthBridgeSet] {
        loggedSets.filter { $0.exerciseKey == exercise.exerciseKey }
    }

    // MARK: session

    public var isSessionActive: Bool { controller.isActive && sessionClientId != nil }

    public func startSession() async {
        guard controller.state == .idle else { return }
        let at = clock()
        await controller.start(at: at)
        guard controller.isActive else { return }
        let id = UUID()
        sessionClientId = id
        await bridge.send(.sessionStarted(StrengthBridgeSessionStart(
            sessionClientId: id, planSessionId: bridge.plan?.planSessionId,
            date: bridge.plan?.date ?? Self.localDay(at), startedAt: at)))
    }

    public func endSession() async {
        guard let id = sessionClientId, controller.isActive else { return }
        stopTimer()
        let at = clock()
        let uuid = await controller.end(at: at)
        await bridge.send(.sessionEnded(StrengthBridgeSessionEnd(sessionClientId: id, endedAt: at, hkWorkoutUUID: uuid)))
    }

    // MARK: entry

    public var weightStepKg: Double {
        guard let s = selected?.stepKg, s > 0 else { return Self.fallbackStepKg }
        return s
    }

    public func select(_ exercise: StrengthWatchExercise) {
        selected = exercise
        editingSetId = nil
        let thisSession = sets(for: exercise).map {
            LoggedSet(exerciseName: exercise.name, category: nil, setNumber: $0.setIndex, reps: $0.reps, weightKg: $0.weightKg)
        }
        let last = exercise.lastSet.map {
            [LoggedSet(exerciseName: exercise.name, category: nil, setNumber: 1, reps: $0.reps, weightKg: $0.weightKg)]
        } ?? []
        let d = LastSetDefaults.resolve(sessionSets: thisSession, planKg: exercise.nextKg, planReps: exercise.targetReps, lastSessionSets: last)
        entryWeightKg = d.weightKg
        entryReps = d.reps
        entryDurationS = sets(for: exercise).last?.durationS ?? exercise.targetDurationS ?? exercise.lastSet?.durationS
    }

    /// Digital Crown value → weight snapped to the exercise's step, never below 0.
    public func setCrownWeight(_ kg: Double) {
        guard kg.isFinite else { return }
        let step = weightStepKg
        entryWeightKg = max(0, (kg / step).rounded(.down) * step)
    }

    public var canLog: Bool {
        guard isSessionActive, let ex = selected else { return false }
        switch ex.kind {
        case .reps: return (entryReps ?? 0) > 0
        case .timed: return (entryDurationS ?? 0) > 0
        }
    }

    // MARK: log / edit / delete

    public func beginEdit(_ set: StrengthBridgeSet) {
        if let ex = exercises.first(where: { $0.exerciseKey == set.exerciseKey }) { selected = ex }
        editingSetId = set.clientId
        entryWeightKg = set.weightKg
        entryReps = set.reps
        entryRpe = set.rpe
        entryDurationS = set.durationS
    }

    public func cancelEdit() { editingSetId = nil }

    /// Logs the entry as a new set (rest auto-starts), or saves the edit of `editingSetId`.
    public func logSet() async {
        guard canLog, let ex = selected else { return }
        await record(ex, durationS: ex.kind == .timed ? entryDurationS : nil)
    }

    public func delete(_ set: StrengthBridgeSet) async {
        guard loggedSets.contains(where: { $0.clientId == set.clientId }) else { return }
        loggedSets.removeAll { $0.clientId == set.clientId }
        if editingSetId == set.clientId { editingSetId = nil }
        await bridge.send(.setDeleted(clientId: set.clientId, sessionClientId: set.sessionClientId))
    }

    /// Double Tap / the big button: log the set (reps), or start / stop the countdown (timed).
    public func primaryAction() async {
        guard let ex = selected, isSessionActive else { return }
        if ex.kind == .timed, editingSetId == nil {
            if timer.phase == .timedSet { await finishTimedSet(early: true) } else { startTimedSet() }
        } else {
            await logSet()
        }
    }

    // MARK: timers (B-5)

    public func startTimedSet() {
        guard let ex = selected, ex.kind == .timed, isSessionActive, let s = entryDurationS, s > 0 else { return }
        let now = clock()
        timedSetSeconds = s
        timedSetStartedAt = now
        timer = timer.startingTimedSet(seconds: s, at: now)
        remainingSeconds = timer.remainingSeconds(at: now)
    }

    public func skipRest() {
        guard timer.phase == .resting else { return }
        stopTimer()
    }

    public func addRest(seconds: Int = 15) {
        guard timer.phase == .resting else { return }
        timer = timer.adding(seconds: seconds)
        remainingSeconds = timer.remainingSeconds(at: clock())
    }

    /// Called once a second by the view (`TimelineView`/`.task`): finishes countdowns, fires the
    /// haptic exactly once per countdown.
    public func tick() async {
        let now = clock()
        remainingSeconds = timer.remainingSeconds(at: now)
        guard timer.isFinished(at: now) else { return }
        switch timer.phase {
        case .resting:
            stopTimer()
            haptic(.restDone)
        case .timedSet:
            await finishTimedSet(early: false)
        case .idle:
            break
        }
    }

    // MARK: private

    private func finishTimedSet(early: Bool) async {
        guard let ex = selected, let planned = timedSetSeconds else { return }
        let now = clock()
        let elapsed = timedSetStartedAt.map { Int(now.timeIntervalSince($0).rounded()) } ?? planned
        let duration = early ? max(1, min(elapsed, planned)) : planned
        stopTimer()
        if !early { haptic(.timedDone) }
        await record(ex, durationS: duration)
    }

    private func record(_ ex: StrengthWatchExercise, durationS: Int?) async {
        guard let session = sessionClientId else { return }
        let isTimed = ex.kind == .timed
        if let editing = editingSetId, let i = loggedSets.firstIndex(where: { $0.clientId == editing }) {
            var s = loggedSets[i]
            s.weightKg = isTimed ? nil : entryWeightKg
            s.reps = isTimed ? nil : entryReps
            s.durationS = isTimed ? durationS : nil
            s.rpe = entryRpe
            loggedSets[i] = s
            editingSetId = nil
            await bridge.send(.setEdited(s))
            return
        }
        let index = (sets(for: ex).map(\.setIndex).max() ?? 0) + 1
        let s = StrengthBridgeSet(clientId: UUID(), sessionClientId: session, exerciseKey: ex.exerciseKey,
                                  exerciseId: ex.exerciseId, setIndex: index, kind: ex.kind,
                                  reps: isTimed ? nil : entryReps,
                                  weightKg: isTimed ? nil : entryWeightKg.flatMap { $0 > 0 ? $0 : nil },
                                  durationS: isTimed ? durationS : nil, rpe: entryRpe, performedAt: clock())
        loggedSets.append(s)
        let now = clock()
        timer = timer.startingRest(seconds: ex.restS.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultRestS, at: now)
        remainingSeconds = timer.remainingSeconds(at: now)
        await bridge.send(.setLogged(s))
    }

    private func stopTimer() {
        timer = timer.stopped()
        remainingSeconds = nil
        timedSetSeconds = nil
        timedSetStartedAt = nil
    }

    static func localDay(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// B-6: the Action Button (`StartStrengthSessionIntent` in the Watch app) and Double Tap reach
/// the live model through here. A press before the UI exists is kept and replayed on attach.
@MainActor
public final class StrengthSessionLauncher {
    public static let shared = StrengthSessionLauncher()
    private var pendingStart = false

    public var model: StrengthLogViewModel? {
        didSet {
            guard pendingStart, let model else { return }
            pendingStart = false
            Task { await model.startSession() }
        }
    }

    public func startFromIntent() async {
        guard let model else { pendingStart = true; return }
        await model.startSession()
    }
}

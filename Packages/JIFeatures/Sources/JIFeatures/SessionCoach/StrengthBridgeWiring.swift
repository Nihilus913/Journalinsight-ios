import Foundation
import SwiftUI
import JICore
import JICompute
import JIPersistence
import JIWorkouts

/// W-B38-B (bridge wiring, phone side) — what the Watch sends lands in the SAME local-first store +
/// `strength` outbox as a set logged on the phone (W-B38-A), so History, the hub row and the
/// Training completion credit cannot tell a Watch set from a phone set.
@MainActor
public final class StrengthBridgeStoreSink: StrengthSessionLogSink {
    private let store: StrengthSessionLogStore
    /// Resolves the strength outbox over the CURRENT hub provider (nil before a connection exists:
    /// the set is still stored locally). Resolved once, then kept, so drains stay serialised.
    private let resolveQueue: () -> StrengthOutbox?
    private var resolved: StrengthOutbox?
    private var queue: StrengthOutbox? {
        if resolved == nil { resolved = resolveQueue() }
        return resolved
    }

    public init(store: StrengthSessionLogStore, queue: @escaping () -> StrengthOutbox?) {
        self.store = store; self.resolveQueue = queue
    }

    public convenience init(store: StrengthSessionLogStore, queue: StrengthOutbox?) {
        self.init(store: store, queue: { queue })
    }

    /// One drain after each write — the hub sees a Watch set as soon as it is reachable.
    private func afterWrite() {
        guard let queue else { return }
        Task { await queue.drainOnce() }
    }

    public func bridgeSessionStarted(_ start: StrengthBridgeSessionStart) async {
        let clientId = start.sessionClientId.uuidString.lowercased()
        guard (try? store.session(clientId: clientId)) == nil else { return }   // replayed start
        let s = StrengthSessionLog(clientId: clientId, sessionId: start.planSessionId, date: start.date,
                                   startedAt: start.startedAt.ISO8601Format())
        try? store.startSession(s)
        queue?.enqueue(.createSession(StrengthSessionCreate(clientId: s.clientId, date: s.date, startedAt: s.startedAt, sessionId: s.sessionId)))
        afterWrite()
    }

    public func bridgeSetLogged(_ set: StrengthBridgeSet) async { write(set, edit: false) }
    public func bridgeSetEdited(_ set: StrengthBridgeSet) async { write(set, edit: true) }

    public func bridgeSetDeleted(clientId: UUID, sessionClientId: UUID) async {
        let id = clientId.uuidString.lowercased()
        try? store.deleteSet(clientId: id)
        queue?.enqueue(.deleteSet(session: sessionClientId.uuidString.lowercased(), clientId: id))
        afterWrite()
    }

    /// The Watch ends the session: `ended_at` locally + a complete with NO advance (progression
    /// is the phone logger's explicit choice, A-3; a Watch session never moves targets by itself).
    public func bridgeSessionEnded(_ end: StrengthBridgeSessionEnd) async {
        let session = end.sessionClientId.uuidString.lowercased()
        let endedAt = end.endedAt.ISO8601Format()
        try? store.complete(sessionClientId: session, endedAt: endedAt)
        queue?.enqueue(.complete(session: session, StrengthSessionComplete(endedAt: endedAt, advance: [])))
        afterWrite()
    }

    private func write(_ b: StrengthBridgeSet, edit: Bool) {
        let s = Self.log(b)
        try? store.upsertSet(s)
        let body = StrengthLogViewModel.body(s)
        queue?.enqueue(edit ? .updateSet(session: s.sessionClientId, body) : .logSet(session: s.sessionClientId, body))
        afterWrite()
    }

    static func log(_ b: StrengthBridgeSet) -> StrengthSetLog {
        StrengthSetLog(clientId: b.clientId.uuidString.lowercased(), sessionClientId: b.sessionClientId.uuidString.lowercased(),
                       exerciseKey: b.exerciseKey, exerciseId: b.exerciseId, setIndex: b.setIndex,
                       kind: b.kind == .timed ? .timed : .reps, reps: b.reps, weightKg: b.weightKg, durationS: b.durationS,
                       rpe: b.rpe, performedAt: b.performedAt.ISO8601Format())
    }
}

/// The plan the phone sends DOWN to the Watch: today's selected training as the A-10 logger
/// prefills it (exercises, sets, reps, nextKg, last sets) + the user's HR limit.
public nonisolated enum StrengthWatchPlanBuilder {
    public static func plan(date: String, planSessionId: Int?, title: String?, lifts: [StrengthLogLift],
                            lastSets: [String: [StrengthSetLog]], settings: GateSettings, restS: Int?) -> StrengthWatchPlan {
        StrengthWatchPlan(
            date: date, planSessionId: planSessionId, title: title,
            hrLimitBpm: SessionCoachViewModel.limitBpm(settings),
            exercises: lifts.map { lift in
                let last = lastSets[lift.exerciseKey]?.last
                return StrengthWatchExercise(
                    exerciseKey: lift.exerciseKey, exerciseId: lift.exerciseId, name: lift.exerciseKey,
                    kind: lift.isTimed ? .timed : .reps, targetSets: lift.sets,
                    targetReps: lift.isTimed ? nil : progressionRepsTarget(lift.repsTarget),
                    targetDurationS: lift.timedSeconds, nextKg: lift.nextKg ?? lift.currentKg, stepKg: lift.stepKg,
                    restS: restS, muscle: StrengthMuscles.targets(for: lift.exerciseKey)?.joined(separator: " · "),
                    lastSet: last.map { StrengthWatchLastSet(weightKg: $0.weightKg, reps: $0.reps, durationS: $0.durationS) })
            })
    }
}

/// The Live Activity state for the feed's current moment: the exercise being worked, the set
/// number to log next, the last set's load, the rest window after it, HR vs the user's limit.
public extension MirroredSessionFeed {
    func activityState(settings: GateSettings, now: Date) -> StrengthSessionActivityState? {
        guard isMirroring, let key = currentExerciseKey else { return nil }
        let done = sets(for: key)
        let last = done.last
        let exercise = plan?.exercises.first { $0.exerciseKey == key }
        let restS = exercise?.restS
        var state = StrengthSessionActivityBuilder.state(
            exercise: exerciseName(key), setNumber: done.count + 1, setCount: exercise?.targetSets,
            weightKg: last?.weightKg ?? exercise?.nextKg, reps: last?.reps ?? exercise?.targetReps,
            durationS: last?.kind == .timed ? last?.durationS : (last == nil ? exercise?.targetDurationS : nil),
            hrBpm: currentHrBpm, settings: settings, now: now)
        if let last, let restS, restS > 0 {
            let end = last.performedAt.addingTimeInterval(TimeInterval(restS))
            if end > now { state.restStartedAt = last.performedAt; state.restEndsAt = end }
        }
        return state
    }
}

/// The App's plan-down hook (`StrengthMirrorCoordinator.sendPlan`); nil in previews / tests.
public extension EnvironmentValues {
    @Entry var strengthWatchPlanSender: ((StrengthWatchPlan) -> Void)? = nil
}

import Foundation
import HealthKit
import JICore
import JIFeatures
import JIPersistence
import JIWorkouts

/// W-B38-B B-8 (+ B-7, bridge wiring) — the phone end of the Watch strength session:
///  · `HKHealthStore.workoutSessionMirroringStartHandler` adopts the Watch's mirrored
///    `HKWorkoutSession` → `MirroredSessionFeed.shared` (the Session Coach's live source);
///  · the mirrored session's data messages + WatchConnectivity user infos go through L1's
///    `StrengthSessionPhoneBridge` → `StrengthBridgeStoreSink` (A-7 store + A-8 outbox) and the feed;
///  · every feed change pushes the strength Live Activity (started on mirror start, ended on end);
///  · `sendPlan` sends today's training down (application context).
@MainActor
final class StrengthMirrorCoordinator: NSObject {
    static let shared = StrengthMirrorCoordinator()

    private let healthStore = HKHealthStore()
    private let feed = MirroredSessionFeed.shared
    private var transport: WatchConnectivityStrengthTransport?
    private var bridge: StrengthSessionPhoneBridge?
    private var mirrored: HKWorkoutSession?
    private var settings: () -> GateSettings = { GateSettings() }
    private var lastActivityPush: Date?
    private var lastActivitySets = -1

    /// HR-only Live Activity refreshes at most this often (a set / rest change always pushes).
    private static let hrPushInterval: TimeInterval = 5

    /// Called once at launch (app mode only). `provider` resolves the CURRENT hub provider for the
    /// strength outbox; `settings` the user's HR limit (cap / Zone 5) for every HR surface.
    func install(prefs: PrefStore, provider: @escaping @MainActor () -> (any TrainingProviding)?,
                 settings: @escaping @MainActor () -> GateSettings) {
        guard transport == nil, HKHealthStore.isHealthDataAvailable() else { return }
        self.settings = settings
        let transport = WatchConnectivityStrengthTransport()
        self.transport = transport
        let db = try? AppDatabase.onDisk()
        if let db {
            let outbox = Outbox(db: db)
            let queue: () -> StrengthOutbox? = { provider().map { StrengthOutbox(outbox: outbox, provider: $0) } }
            let sink = StrengthBridgeStoreSink(store: StrengthSessionLogStore(db: db), queue: queue)
            let bridge = StrengthSessionPhoneBridge(transport: transport, sink: sink)
            bridge.onEvent = { [weak self] event in self?.feed.ingest(event) }
            self.bridge = bridge
            transport.onUserInfo = { [weak self] info in
                Task { @MainActor in await self?.bridge?.receive(userInfo: info) }
            }
        }
        feed.isAvailable = true
        feed.onChange = { [weak self] in self?.pushActivity() }
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.adopt(session) }
        }
    }

    /// Plan down (latest wins; delivered when the Watch app wakes).
    func sendPlan(_ plan: StrengthWatchPlan) {
        feed.plan = plan
        try? bridge?.sendPlan(plan)
    }

    private func adopt(_ session: HKWorkoutSession) {
        mirrored = session
        session.delegate = self
        feed.mirrorStarted(at: session.startDate ?? Date())
    }

    private func mirrorFinished() {
        mirrored = nil
        feed.mirrorEnded()
    }

    private func pushActivity() {
        let now = Date()
        let controller = StrengthSessionActivityController.shared
        guard let state = feed.activityState(settings: settings(), now: now) else {
            if !feed.isMirroring { controller.end(); lastActivityPush = nil; lastActivitySets = -1 }
            return
        }
        if !controller.isRunning {
            controller.start(startedAt: feed.startedAt ?? now, state: state)
        } else {
            let setsChanged = feed.sets.count != lastActivitySets
            if !setsChanged, let last = lastActivityPush, now.timeIntervalSince(last) < Self.hrPushInterval { return }
            controller.update(state)
        }
        lastActivityPush = now
        lastActivitySets = feed.sets.count
    }
}

extension StrengthMirrorCoordinator: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.mirrorFinished() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.mirrorFinished() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for message in data { await self.bridge?.receive(message) }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        Task { @MainActor in self.mirrorFinished() }
    }
}

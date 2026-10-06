import Foundation
import Observation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if os(watchOS)
import HealthKit
#endif

// W-B38-B B-3 (gap #26/#30): the Watch ⇄ iPhone strength bridge.
//  · plan DOWN (phone → watch): today's exercises + nextKg + last-set defaults, via the
//    WCSession application context (latest-wins, delivered when the Watch app wakes).
//  · sets UP (watch → phone): over the mirrored workout session (`sendToRemoteWorkoutSession`),
//    `transferUserInfo` fallback when not mirrored / the send fails (queued, never lost).
//  · the phone side writes every event into a `StrengthSessionLogSink` — the App wires that to
//    W-B38-A's `StrengthSessionLogStore` (→ Outbox kind `strength`).
//
// PHONE API (fixed at launch for L2 — B-7/B-8 consume it):
//   StrengthSessionPhoneBridge(transport:sink:)  · sendPlan(_:) throws
//   receive(_ data: Data) async                  ← HKWorkoutSessionDelegate didReceiveDataFromRemoteWorkoutSession
//   receive(userInfo:) async                     ← WCSessionDelegate didReceiveUserInfo
//   onEvent: ((StrengthBridgeEvent) -> Void)?    ← live view (SessionCoach / Live Activity), incl. .heartRate
//   StrengthSessionLogSink                       ← the store adapter (5 async methods)

public enum StrengthSetKind: String, Codable, Sendable, Equatable { case reps, timed }

/// The last logged set of an exercise (prefill, gap #29). nil fields = unknown (never 0).
public struct StrengthWatchLastSet: Codable, Sendable, Equatable {
    public var weightKg: Double?
    public var reps: Int?
    public var durationS: Int?
    public init(weightKg: Double?, reps: Int?, durationS: Int?) {
        self.weightKg = weightKg; self.reps = reps; self.durationS = durationS
    }
}

public struct StrengthWatchExercise: Codable, Sendable, Equatable, Identifiable {
    public var id: String { exerciseKey }
    public var exerciseKey: String
    /// `plan.session_exercises` id (the hub's `exercise_id`), nil for library extras.
    public var exerciseId: Int?
    public var name: String
    public var kind: StrengthSetKind
    public var targetSets: Int?
    public var targetReps: Int?
    public var targetDurationS: Int?
    /// `ProgressionService` nextKg for today.
    public var nextKg: Double?
    /// The Digital Crown step for this exercise's weight (2.5 barbell, 1.25 microplates, 2 dumbbell…).
    public var stepKg: Double?
    public var restS: Int?
    /// Targeted muscle(s) — the preview (Toby 2026-10-03: muscle, no animation).
    public var muscle: String?
    public var lastSet: StrengthWatchLastSet?

    public init(exerciseKey: String, exerciseId: Int?, name: String, kind: StrengthSetKind, targetSets: Int?,
                targetReps: Int?, targetDurationS: Int?, nextKg: Double?, stepKg: Double?, restS: Int?,
                muscle: String?, lastSet: StrengthWatchLastSet?) {
        self.exerciseKey = exerciseKey; self.exerciseId = exerciseId; self.name = name; self.kind = kind
        self.targetSets = targetSets; self.targetReps = targetReps; self.targetDurationS = targetDurationS
        self.nextKg = nextKg; self.stepKg = stepKg; self.restS = restS; self.muscle = muscle; self.lastSet = lastSet
    }
}

/// Today's strength plan as the Watch sees it.
public struct StrengthWatchPlan: Codable, Sendable, Equatable {
    public var date: String // yyyy-MM-dd, the plan day
    public var planSessionId: Int?
    public var title: String?
    /// `SessionCap.limitBpm(...)` computed on the phone (175 cap / no Zone 5); nil = no limit.
    public var hrLimitBpm: Int?
    public var exercises: [StrengthWatchExercise]

    public init(date: String, planSessionId: Int?, title: String?, hrLimitBpm: Int?, exercises: [StrengthWatchExercise]) {
        self.date = date; self.planSessionId = planSessionId; self.title = title
        self.hrLimitBpm = hrLimitBpm; self.exercises = exercises
    }
}

/// One logged set — the same keys as the hub's `plan.strength_set_log` row.
public struct StrengthBridgeSet: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { clientId }
    public var clientId: UUID
    public var sessionClientId: UUID
    public var exerciseKey: String
    public var exerciseId: Int?
    public var setIndex: Int
    public var kind: StrengthSetKind
    public var reps: Int?
    public var weightKg: Double?
    public var durationS: Int?
    public var rpe: Double?
    public var performedAt: Date

    public init(clientId: UUID, sessionClientId: UUID, exerciseKey: String, exerciseId: Int?, setIndex: Int,
                kind: StrengthSetKind, reps: Int?, weightKg: Double?, durationS: Int?, rpe: Double?, performedAt: Date) {
        self.clientId = clientId; self.sessionClientId = sessionClientId; self.exerciseKey = exerciseKey
        self.exerciseId = exerciseId; self.setIndex = setIndex; self.kind = kind; self.reps = reps
        self.weightKg = weightKg; self.durationS = durationS; self.rpe = rpe; self.performedAt = performedAt
    }
}

public struct StrengthBridgeSessionStart: Codable, Sendable, Equatable {
    public var sessionClientId: UUID
    public var planSessionId: Int?
    public var date: String
    public var startedAt: Date
    public init(sessionClientId: UUID, planSessionId: Int?, date: String, startedAt: Date) {
        self.sessionClientId = sessionClientId; self.planSessionId = planSessionId; self.date = date; self.startedAt = startedAt
    }
}

public struct StrengthBridgeSessionEnd: Codable, Sendable, Equatable {
    public var sessionClientId: UUID
    public var endedAt: Date
    /// The saved `HKWorkout.uuid` → `plan.strength_session.hk_workout_uuid`.
    public var hkWorkoutUUID: UUID?
    public init(sessionClientId: UUID, endedAt: Date, hkWorkoutUUID: UUID?) {
        self.sessionClientId = sessionClientId; self.endedAt = endedAt; self.hkWorkoutUUID = hkWorkoutUUID
    }
}

public enum StrengthBridgeEvent: Codable, Sendable, Equatable {
    case sessionStarted(StrengthBridgeSessionStart)
    case setLogged(StrengthBridgeSet)
    case setEdited(StrengthBridgeSet)
    case setDeleted(clientId: UUID, sessionClientId: UUID)
    /// Live only — sent over the mirror, never queued (a stale reading is worse than none).
    case heartRate(bpm: Int, at: Date)
    case sessionEnded(StrengthBridgeSessionEnd)

    var isLiveOnly: Bool { if case .heartRate = self { true } else { false } }
}

public struct StrengthBridgeEnvelope: Codable, Sendable, Equatable {
    public var messageId: UUID
    public var event: StrengthBridgeEvent

    public init(messageId: UUID = UUID(), event: StrengthBridgeEvent) {
        self.messageId = messageId; self.event = event
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> StrengthBridgeEnvelope {
        try JSONDecoder().decode(StrengthBridgeEnvelope.self, from: data)
    }
}

public enum StrengthBridgeKeys {
    public static let event = "strength"
    public static let plan = "strengthPlan"
    /// W-B78 (B-78): the HubSnapshot glance wire — must equal `SnapshotWire.key` (JISnapshot).
    public static let snapshot = "ji.snapshot"
}

/// W-B78 (B-78): splits one received application context between its two owners — the strength
/// plan (`plan`, handed the `[plan: Data]` dict the watch bridge already reads) and the HubSnapshot
/// glances (`snapshot`, handed the raw wire bytes). Absent keys call nothing.
public enum StrengthBridgeContextRouter {
    public static func route(_ context: [String: Any], plan: ([String: Any]) -> Void, snapshot: (Data) -> Void) {
        if let data = context[StrengthBridgeKeys.plan] as? Data { plan([StrengthBridgeKeys.plan: data]) }
        if let data = context[StrengthBridgeKeys.snapshot] as? Data { snapshot(data) }
    }
}

/// The wire. Real conformance: `WatchConnectivityStrengthTransport`.
@MainActor
public protocol StrengthBridgeTransport: AnyObject {
    var canSendToRemoteWorkoutSession: Bool { get }
    func sendToRemoteWorkoutSession(_ data: Data) async throws
    func transferUserInfo(_ info: [String: Any])
    func updateApplicationContext(_ context: [String: Any]) throws
    /// W-B78: sets ONE key of the application context and keeps every other key (the plan and the
    /// HubSnapshot share the context; a bare `updateApplicationContext` would erase the other).
    func mergeApplicationContext(key: String, value: Data) throws
}

/// The phone-side store adapter (App wires it to `StrengthSessionLogStore`).
@MainActor
public protocol StrengthSessionLogSink: AnyObject {
    func bridgeSessionStarted(_ start: StrengthBridgeSessionStart) async
    func bridgeSetLogged(_ set: StrengthBridgeSet) async
    func bridgeSetEdited(_ set: StrengthBridgeSet) async
    func bridgeSetDeleted(clientId: UUID, sessionClientId: UUID) async
    func bridgeSessionEnded(_ end: StrengthBridgeSessionEnd) async
}

// MARK: - Watch side

@MainActor
@Observable
public final class StrengthSessionWatchBridge {
    /// Latest plan from the phone; nil until one arrives (the Watch shows "Open JournalInsight
    /// on your iPhone" — never an invented plan).
    public private(set) var plan: StrengthWatchPlan?
    @ObservationIgnored private let transport: StrengthBridgeTransport

    public init(transport: StrengthBridgeTransport) { self.transport = transport }

    public func receive(applicationContext: [String: Any]) {
        guard let data = applicationContext[StrengthBridgeKeys.plan] as? Data,
              let decoded = try? JSONDecoder().decode(StrengthWatchPlan.self, from: data) else { return }
        plan = decoded
    }

    public func send(_ event: StrengthBridgeEvent) async {
        guard let data = try? StrengthBridgeEnvelope(event: event).encoded() else { return }
        if transport.canSendToRemoteWorkoutSession {
            do {
                try await transport.sendToRemoteWorkoutSession(data)
                return
            } catch {
                // fall through to the queued path
            }
        }
        guard !event.isLiveOnly else { return }
        transport.transferUserInfo([StrengthBridgeKeys.event: data])
    }
}

// MARK: - Phone side

@MainActor
public final class StrengthSessionPhoneBridge {
    public var onEvent: ((StrengthBridgeEvent) -> Void)?
    private let transport: StrengthBridgeTransport
    private let sink: StrengthSessionLogSink
    private var seenMessages: Set<UUID> = []
    private var loggedSets: Set<UUID> = []

    public init(transport: StrengthBridgeTransport, sink: StrengthSessionLogSink) {
        self.transport = transport; self.sink = sink
    }

    public func sendPlan(_ plan: StrengthWatchPlan) throws {
        try transport.mergeApplicationContext(key: StrengthBridgeKeys.plan, value: try JSONEncoder().encode(plan))
    }

    public func receive(userInfo: [String: Any]) async {
        guard let data = userInfo[StrengthBridgeKeys.event] as? Data else { return }
        await receive(data)
    }

    public func receive(_ data: Data) async {
        guard let env = try? StrengthBridgeEnvelope.decode(data),
              seenMessages.insert(env.messageId).inserted else { return }
        switch env.event {
        case .sessionStarted(let s): await sink.bridgeSessionStarted(s)
        case .setLogged(let s):
            // The same set can arrive over the mirror AND the userInfo fallback.
            guard loggedSets.insert(s.clientId).inserted else { return }
            await sink.bridgeSetLogged(s)
        case .setEdited(let s): await sink.bridgeSetEdited(s)
        case .setDeleted(let id, let session): await sink.bridgeSetDeleted(clientId: id, sessionClientId: session)
        case .heartRate: break
        case .sessionEnded(let e): await sink.bridgeSessionEnded(e)
        }
        onEvent?(env.event)
    }
}

// MARK: - Fake transport

@MainActor
public final class FakeStrengthBridgeTransport: StrengthBridgeTransport {
    public enum Failure: Error { case notReachable }
    public var canSendToRemoteWorkoutSession = false
    public var remoteError: Error?
    public private(set) var remoteSends: [Data] = []
    public private(set) var userInfos: [[String: Any]] = []
    public private(set) var applicationContext: [String: Any] = [:]

    public init() {}

    public func sendToRemoteWorkoutSession(_ data: Data) async throws {
        if let remoteError { throw remoteError }
        remoteSends.append(data)
    }
    public func transferUserInfo(_ info: [String: Any]) { userInfos.append(info) }
    public func updateApplicationContext(_ context: [String: Any]) throws { applicationContext = context }
    public func mergeApplicationContext(key: String, value: Data) throws {
        var merged = applicationContext
        merged[key] = value
        applicationContext = merged
    }
}

// MARK: - WatchConnectivity transport

#if canImport(WatchConnectivity) && !os(macOS)
/// The real wire: one `WCSession` (activated here) + the mirrored workout session when there is
/// one. Incoming traffic is handed to `onUserInfo` (phone) / `onApplicationContext` (watch, the
/// plan) / `onSnapshotContext` (watch, W-B78 HubSnapshot wire bytes).
@MainActor
public final class WatchConnectivityStrengthTransport: NSObject, StrengthBridgeTransport {
    public var onUserInfo: (([String: Any]) -> Void)?
    public var onApplicationContext: (([String: Any]) -> Void)?
    /// W-B78: the HubSnapshot bytes (`StrengthBridgeKeys.snapshot`) from a received context.
    public var onSnapshotContext: ((Data) -> Void)?
    #if os(watchOS)
    /// Set while a mirrored strength session runs (`HealthKitStrengthWorkoutEngine.workoutSession`).
    public var workoutSession: HKWorkoutSession?
    #endif

    private let session: WCSession?

    public override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    public var canSendToRemoteWorkoutSession: Bool {
        #if os(watchOS)
        workoutSession != nil
        #else
        false
        #endif
    }

    public func sendToRemoteWorkoutSession(_ data: Data) async throws {
        #if os(watchOS)
        guard let workoutSession else { throw CocoaError(.featureUnsupported) }
        try await workoutSession.sendToRemoteWorkoutSession(data: data)
        #else
        throw CocoaError(.featureUnsupported)
        #endif
    }

    public func transferUserInfo(_ info: [String: Any]) { session?.transferUserInfo(info) }

    public func updateApplicationContext(_ context: [String: Any]) throws {
        try session?.updateApplicationContext(context)
    }

    /// `session.applicationContext` is the last context THIS side sent — merge into it.
    public func mergeApplicationContext(key: String, value: Data) throws {
        guard let session else { return }
        var merged = session.applicationContext
        merged[key] = value
        try session.updateApplicationContext(merged)
    }

    /// The one entry point for any received context (activation backlog or live delivery).
    func deliver(_ context: [String: Data]) {
        StrengthBridgeContextRouter.route(context, plan: { onApplicationContext?($0) }, snapshot: { onSnapshotContext?($0) })
    }

    /// W-B78 B78-2: session activated (both sides) or, on the phone, the Watch state changed.
    public var onSessionChange: (() -> Void)?

    /// W-B78 B78-2: phone side — false when unpaired / the Watch app is absent (always true on watchOS).
    public var isCounterpartAppInstalled: Bool {
        #if os(iOS)
        guard let session, session.activationState == .activated else { return false }
        return session.isPaired && session.isWatchAppInstalled
        #else
        return session != nil
        #endif
    }

    /// The context already delivered before the delegate was set (Watch cold start).
    public var receivedApplicationContext: [String: Any] { session?.receivedApplicationContext ?? [:] }
}

extension WatchConnectivityStrengthTransport: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // W-B78 B78-2: the phone re-pushes the latest HubSnapshot once the session is usable.
        if activationState == .activated { Task { @MainActor [weak self] in self?.onSessionChange?() } }
        // A plan / snapshot delivered while the app was not running is only in `receivedApplicationContext`.
        let context = Self.wireKeys(session.receivedApplicationContext)
        guard !context.isEmpty else { return }
        Task { @MainActor [weak self] in self?.deliver(context) }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    /// W-B78 B78-2: paired / Watch-app-installed changed — the phone re-pushes the snapshot.
    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.onSessionChange?() }
    }
    #endif

    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[StrengthBridgeKeys.event] as? Data else { return }
        Task { @MainActor [weak self] in self?.onUserInfo?([StrengthBridgeKeys.event: data]) }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let context = Self.wireKeys(applicationContext)
        guard !context.isEmpty else { return }
        Task { @MainActor [weak self] in self?.deliver(context) }
    }

    /// Only the two Data keys cross the actor hop (`[String: Data]` is Sendable).
    nonisolated static func wireKeys(_ context: [String: Any]) -> [String: Data] {
        var out: [String: Data] = [:]
        for key in [StrengthBridgeKeys.plan, StrengthBridgeKeys.snapshot] {
            if let data = context[key] as? Data { out[key] = data }
        }
        return out
    }
}
#endif

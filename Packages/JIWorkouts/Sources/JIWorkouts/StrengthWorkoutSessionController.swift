import Foundation
import Observation
#if os(watchOS)
import HealthKit
#endif

// W-B38-B B-2 (gap #26/#30): the Watch runs a strength session as a real HealthKit workout —
// `HKWorkoutSession` + `HKLiveWorkoutBuilder`, `.traditionalStrengthTraining`, live HR, mirrored
// to the iPhone (`startMirroringToCompanionDevice`). The saved `HKWorkout.uuid` is what the
// session log carries as `hk_workout_uuid`. The HealthKit side sits behind
// `StrengthWorkoutEngine` so the state machine is tested without a Watch.

public enum StrengthWorkoutState: Sendable, Equatable {
    case idle, running, paused, ending, ended
}

/// The HealthKit seam. Real conformance: `HealthKitStrengthWorkoutEngine` (watchOS only).
@MainActor
public protocol StrengthWorkoutEngine: AnyObject {
    /// Set by the controller; the engine calls it with every live HR sample (bpm).
    var onHeartRate: ((Double, Date) -> Void)? { get set }
    func start(at date: Date) async throws
    func startMirroring() async throws
    func pause()
    func resume()
    /// Ends the session and saves the workout; returns the saved `HKWorkout.uuid` (nil when
    /// HealthKit saved nothing).
    func end(at date: Date) async throws -> UUID?
}

@MainActor
@Observable
public final class StrengthWorkoutSessionController {
    public private(set) var state: StrengthWorkoutState = .idle
    public private(set) var startedAt: Date?
    public private(set) var isMirrored = false
    /// Latest live HR, rounded to whole bpm; nil until the first reading (never a zero).
    public private(set) var heartRateBpm: Int?
    public private(set) var heartRateAt: Date?
    public private(set) var hkWorkoutUUID: UUID?
    public private(set) var errorMessage: String?

    /// Forwarded live HR (whole bpm) — the bridge / cap gauge listen here.
    @ObservationIgnored public var onHeartRate: ((Int) -> Void)?
    /// Called once when the session ended (with the saved workout's uuid, if any).
    @ObservationIgnored public var onEnded: ((UUID?) -> Void)?

    @ObservationIgnored private let engine: StrengthWorkoutEngine

    public init(engine: StrengthWorkoutEngine) {
        self.engine = engine
        engine.onHeartRate = { [weak self] bpm, date in self?.receive(bpm: bpm, at: date) }
    }

    public var isActive: Bool { state == .running || state == .paused }

    public func start(at date: Date) async {
        guard state == .idle else { return }
        state = .running // claim the slot before awaiting, a second tap is a no-op
        errorMessage = nil
        do {
            try await engine.start(at: date)
        } catch {
            state = .idle
            errorMessage = "Couldn't start the workout: \(error.localizedDescription)"
            return
        }
        startedAt = date
        do {
            try await engine.startMirroring()
            isMirrored = true
        } catch {
            isMirrored = false // phone not reachable: sets go via transferUserInfo (B-3)
        }
    }

    public func pause() {
        guard state == .running else { return }
        engine.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        engine.resume()
        state = .running
    }

    /// Ends and saves the workout exactly once; later calls return the same uuid.
    @discardableResult
    public func end(at date: Date) async -> UUID? {
        guard isActive else { return hkWorkoutUUID }
        state = .ending
        do {
            hkWorkoutUUID = try await engine.end(at: date)
        } catch {
            errorMessage = "The workout ended but Health didn't save it: \(error.localizedDescription)"
        }
        state = .ended
        onEnded?(hkWorkoutUUID)
        return hkWorkoutUUID
    }

    private func receive(bpm: Double, at date: Date) {
        guard isActive, bpm.isFinite, bpm > 0 else { return }
        let whole = Int(bpm.rounded())
        heartRateBpm = whole
        heartRateAt = date
        onHeartRate?(whole)
    }
}

/// Test / preview engine — records calls, emits HR on demand.
@MainActor
public final class FakeStrengthWorkoutEngine: StrengthWorkoutEngine {
    public enum Failure: Error { case boom }
    public var onHeartRate: ((Double, Date) -> Void)?
    public var startError: Error?
    public var mirrorError: Error?
    public var savedUUID: UUID?
    public private(set) var startCount = 0, mirrorCount = 0, pauseCount = 0, resumeCount = 0, endCount = 0

    public init() {}

    public func start(at date: Date) async throws {
        startCount += 1
        if let startError { throw startError }
    }
    public func startMirroring() async throws {
        mirrorCount += 1
        if let mirrorError { throw mirrorError }
    }
    public func pause() { pauseCount += 1 }
    public func resume() { resumeCount += 1 }
    public func end(at date: Date) async throws -> UUID? {
        endCount += 1
        return savedUUID
    }
    public func emitHeartRate(_ bpm: Double, at date: Date) { onHeartRate?(bpm, date) }
}

#if os(watchOS)
/// The real engine: `HKWorkoutSession` + `HKLiveWorkoutBuilder` for traditional strength
/// training, live HR from the builder's statistics, mirrored to the companion iPhone.
@MainActor
public final class HealthKitStrengthWorkoutEngine: NSObject, StrengthWorkoutEngine {
    public var onHeartRate: ((Double, Date) -> Void)?
    private let store: HKHealthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    public init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    public static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
    }
    public static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
    }

    public func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    public func start(at date: Date) async throws {
        try await requestAuthorization()
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let session = try HKWorkoutSession(healthStore: store, configuration: config)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        builder.delegate = self
        self.session = session
        self.builder = builder
        session.startActivity(with: date)
        try await builder.beginCollection(at: date)
    }

    public func startMirroring() async throws {
        guard let session else { return }
        try await session.startMirroringToCompanionDevice()
    }

    public func pause() { session?.pause() }
    public func resume() { session?.resume() }

    public func end(at date: Date) async throws -> UUID? {
        guard let session, let builder else { return nil }
        session.stopActivity(with: date)
        session.end()
        try await builder.endCollection(at: date)
        let workout = try await builder.finishWorkout()
        self.session = nil
        self.builder = nil
        return workout?.uuid
    }

    /// The mirrored session — the bridge sends set messages over it (`sendToRemoteWorkoutSession`).
    public var workoutSession: HKWorkoutSession? { session }
}

extension HealthKitStrengthWorkoutEngine: HKLiveWorkoutBuilderDelegate {
    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hr),
              let quantity = workoutBuilder.statistics(for: hr)?.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        let at = Date.now
        Task { @MainActor [weak self] in self?.onHeartRate?(bpm, at) }
    }
}
#endif

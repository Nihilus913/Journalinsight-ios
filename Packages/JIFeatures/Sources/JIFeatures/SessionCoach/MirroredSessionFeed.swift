import Foundation
import Observation
import JICore
import JIWorkouts

/// W-B38-B B-8 — the phone's view of the strength session running on the Apple Watch, fed by the
/// HealthKit mirroring start handler (`HKHealthStore.workoutSessionMirroringStartHandler`, App) and
/// the strength bridge's events (`StrengthSessionPhoneBridge.onEvent`: HR ticks + sets as they land).
///
/// The FIRST real `LiveSessionProviding`: the Session Coach polls it exactly like the mock feed.
/// Honesty rules (CLAUDE.md rule 5): no mirror running → `liveSession()` throws `.notMirroring`
/// (the coach shows why, never a zero); an HR reading older than `hrStaleAfter` is reported as
/// nil (`.unknown` cap state — a stale reading is never an all-clear).
@Observable @MainActor
public final class MirroredSessionFeed: LiveSessionProviding {
    public enum FeedError: Error, Equatable, LocalizedError {
        case notMirroring
        public var errorDescription: String? {
            "Start a strength workout on your Apple Watch — its heart rate and sets show here live."
        }
    }

    public static let shared = MirroredSessionFeed()
    public nonisolated static let hrStaleAfter: TimeInterval = 15

    public private(set) var isMirroring = false
    public private(set) var startedAt: Date?
    public private(set) var sessionClientId: UUID?
    public private(set) var hrBpm: Int?
    public private(set) var hrAt: Date?
    /// Sets logged on the Watch this session, in `performedAt` order (edits replace, deletes remove).
    public private(set) var sets: [StrengthBridgeSet] = []
    /// Today's plan as sent to the Watch (exercise names + planned set counts); nil = none sent.
    public var plan: StrengthWatchPlan?
    /// Called after every change (the App pushes the Live Activity from here).
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) { self.now = now }

    // MARK: inputs

    /// The mirrored `HKWorkoutSession` reached the phone.
    public func mirrorStarted(at date: Date) {
        if !isMirroring { sets = []; hrBpm = nil; hrAt = nil }
        isMirroring = true
        startedAt = startedAt ?? date
        onChange?()
    }

    /// The mirrored session ended (or failed) — the feed goes quiet.
    public func mirrorEnded() {
        isMirroring = false
        startedAt = nil
        sessionClientId = nil
        hrBpm = nil
        hrAt = nil
        onChange?()
    }

    public func ingest(_ event: StrengthBridgeEvent) {
        switch event {
        case .sessionStarted(let s):
            if sessionClientId != s.sessionClientId { sets = [] }
            sessionClientId = s.sessionClientId
            startedAt = s.startedAt
            isMirroring = true
        case .heartRate(let bpm, let at):
            guard hrAt.map({ at >= $0 }) ?? true else { return }   // out-of-order tick
            hrBpm = bpm; hrAt = at
        case .setLogged(let s):
            guard !sets.contains(where: { $0.clientId == s.clientId }) else { return }
            sets.append(s)
            sets.sort { $0.performedAt < $1.performedAt }
        case .setEdited(let s):
            if let i = sets.firstIndex(where: { $0.clientId == s.clientId }) { sets[i] = s }
        case .setDeleted(let id, _):
            sets.removeAll { $0.clientId == id }
        case .sessionEnded:
            mirrorEnded()
            return
        }
        onChange?()
    }

    // MARK: derived

    /// The HR to show: nil when none arrived or the last one is older than `hrStaleAfter`.
    public var currentHrBpm: Int? {
        guard let hrBpm, let hrAt, now().timeIntervalSince(hrAt) <= Self.hrStaleAfter else { return nil }
        return hrBpm
    }

    /// The exercise of the last logged set, else the plan's first.
    public var currentExerciseKey: String? { sets.last?.exerciseKey ?? plan?.exercises.first?.exerciseKey }

    public func exerciseName(_ key: String) -> String {
        plan?.exercises.first(where: { $0.exerciseKey == key })?.name ?? key
    }

    public func plannedSets(_ key: String) -> Int? { plan?.exercises.first(where: { $0.exerciseKey == key })?.targetSets }

    public func sets(for key: String) -> [StrengthBridgeSet] { sets.filter { $0.exerciseKey == key } }

    /// Planned sets across the plan (session load target); 0 when there is no plan.
    public var plannedSetTotal: Int { plan?.exercises.compactMap(\.targetSets).reduce(0, +) ?? 0 }

    // MARK: LiveSessionProviding

    /// Hops to the main actor (the feed's state lives there; the protocol requirement is nonisolated).
    public nonisolated func liveSession() async throws -> LiveSessionSample {
        try await MainActor.run { try self.currentSample() }
    }

    public func currentSample() throws -> LiveSessionSample {
        guard isMirroring, let startedAt else { throw FeedError.notMirroring }
        return LiveSessionSample(hrBpm: currentHrBpm, elapsedS: max(0, Int(now().timeIntervalSince(startedAt))),
                                 load: Double(sets.count), targetLoad: Double(plannedSetTotal))
    }
}

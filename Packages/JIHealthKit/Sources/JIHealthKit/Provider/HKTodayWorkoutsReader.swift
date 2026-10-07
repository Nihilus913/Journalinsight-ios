#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore

/// W-FIX7 F7-1: one workout as Health stores it — the fields the today reader needs, so tests
/// never have to build an `HKWorkout` (and its source) by hand.
public struct HKWorkoutRecord: Sendable, Equatable {
    public var activityType: HKWorkoutActivityType
    public var start: Date
    public var end: Date
    public var sourceName: String?
    /// W-OFFLINE2 OFF2-4: the workout's own statistics for the no-hub Training history (nil = not
    /// recorded — never shown as zero). Defaulted so the today reader's callers stay unchanged.
    public var distanceM: Double?
    public var avgHRBpm: Double?
    public var maxHRBpm: Double?
    public init(activityType: HKWorkoutActivityType, start: Date, end: Date, sourceName: String?,
                distanceM: Double? = nil, avgHRBpm: Double? = nil, maxHRBpm: Double? = nil) {
        self.activityType = activityType; self.start = start; self.end = end; self.sourceName = sourceName
        self.distanceM = distanceM; self.avgHRBpm = avgHRBpm; self.maxHRBpm = maxHRBpm
    }
}

/// Seam: every workout in `[start, end)` from ANY source (Bevel, Apple Workout, this app's own
/// Garmin backload) — unlike `HealthStoreReading.workouts`, which leaves this app's out on purpose.
public protocol HealthStoreWorkoutQuerying: Sendable {
    func allWorkouts(start: Date, end: Date) async throws -> [HKWorkoutRecord]
}

extension RealHealthStoreReader: HealthStoreWorkoutQuerying {
    public func allWorkouts(start: Date, end: Date) async throws -> [HKWorkoutRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKWorkoutType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, error in
                if let error {
                    // Not granted / nothing stored = no workouts (rule 5), never a failure.
                    if let code = (error as? HKError)?.code, code == .errorNoData || code == .errorAuthorizationNotDetermined {
                        continuation.resume(returning: []); return
                    }
                    continuation.resume(throwing: error); return
                }
                let bpm = HKUnit.count().unitDivided(by: .minute())
                let rows = (samples ?? []).compactMap { $0 as? HKWorkout }.map { w in
                    let hr = w.statistics(for: HKWorkoutUploadTypes.heartRate)
                    let distance = HKWorkoutUploadTypes.distances.lazy
                        .compactMap { w.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }.first
                    return HKWorkoutRecord(activityType: w.workoutActivityType, start: w.startDate, end: w.endDate,
                                           sourceName: w.sourceRevision.source.name, distanceM: distance,
                                           avgHRBpm: hr?.averageQuantity()?.doubleValue(for: bpm),
                                           maxHRBpm: hr?.maximumQuantity()?.doubleValue(for: bpm))
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }
}

/// W-FIX7 F7-1 (S1): today's workouts straight from Apple Health (local calendar day, every
/// source), as JICore `TodayWorkout`s. Read authorization for `HKWorkoutType` is already part of
/// `HKReadKind.workouts` (the permission sheet's read set); an ungranted read returns [].
public struct HKTodayWorkoutsReader: TodayWorkoutsProviding {
    private let store: any HealthStoreWorkoutQuerying
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        store: any HealthStoreWorkoutQuerying,
        calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store; self.calendar = calendar; self.now = now
    }

    public func todayWorkouts() async throws -> [TodayWorkout] { try await fetch() }

    /// Off the caller's actor (2026-09-23 lesson: HealthKit reads on the MainActor froze the app).
    @concurrent
    private func fetch() async throws -> [TodayWorkout] {
        let start = calendar.startOfDay(for: now())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let calendar = self.calendar
        return try await store.allWorkouts(start: start, end: end)
            // A workout belongs to the day it started on (a 23:30 run is yesterday's, not today's).
            .filter { calendar.isDate($0.start, inSameDayAs: start) }
            .sorted { $0.start < $1.start }
            .map { Self.todayWorkout($0) }
    }

    static func todayWorkout(_ r: HKWorkoutRecord) -> TodayWorkout {
        TodayWorkout(kind: kind(of: r.activityType), activityName: name(of: r.activityType),
                     start: r.start, end: r.end, sourceName: r.sourceName)
    }

    /// strength ↔ traditional / functional strength; cardio ↔ run, cycle, walk, elliptical, rower, …
    public static func kind(of type: HKWorkoutActivityType) -> TodayWorkout.Kind {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return .strength
        case .running, .cycling, .walking, .elliptical, .rowing, .stairClimbing, .stairs, .stepTraining,
             .hiking, .swimming, .highIntensityIntervalTraining, .mixedCardio, .crossCountrySkiing,
             .handCycling, .paddleSports, .jumpRope, .wheelchairRunPace, .wheelchairWalkPace, .skatingSports:
            return .cardio
        default:
            return .other
        }
    }

    public static func name(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: "Traditional strength"
        case .functionalStrengthTraining: "Functional strength"
        case .running: "Run"
        case .cycling: "Cycling"
        case .walking: "Walk"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing, .stairs: "Stairs"
        case .stepTraining: "Step training"
        case .hiking: "Hike"
        case .swimming: "Swim"
        case .highIntensityIntervalTraining: "HIIT"
        case .mixedCardio: "Mixed cardio"
        case .crossCountrySkiing: "Cross-country skiing"
        case .handCycling: "Hand cycling"
        case .paddleSports: "Paddling"
        case .jumpRope: "Jump rope"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .coreTraining: "Core training"
        case .flexibility: "Flexibility"
        case .cooldown: "Cooldown"
        case .crossTraining: "Cross training"
        default: "Workout"
        }
    }
}
#endif

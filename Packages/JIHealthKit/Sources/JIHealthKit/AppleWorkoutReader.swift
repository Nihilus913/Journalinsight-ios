#if canImport(HealthKit)
import CoreLocation
import Foundation
import HealthKit

/// W-B81 A-4: one page of the anchored `HKWorkout` query, already turned into records.
/// `fetchedCount` = the objects HealthKit returned BEFORE the hub-backload filter, so the uploader
/// can tell a full page ("there may be more") from a filtered one.
public struct AppleWorkoutPage: Sendable {
    public var records: [AppleWorkoutRecord]
    public var fetchedCount: Int
    public var newAnchor: HKQueryAnchor?
    public init(records: [AppleWorkoutRecord], fetchedCount: Int, newAnchor: HKQueryAnchor?) {
        self.records = records; self.fetchedCount = fetchedCount; self.newAnchor = newAnchor
    }
}

/// Read seam for the Apple-workout upload (the real reader conforms; tests inject a fake).
/// Deleted workouts are deliberately not surfaced: the phone never deletes hub rows (X-1).
public protocol HealthStoreWorkoutUploadReading: Sendable {
    /// Workouts new/changed since `anchor` (`since` bounds the very first read), at most `limit`
    /// HealthKit objects, with each workout's statistics, HR series, route, efforts and zones.
    /// A detail read that fails throws — never a record with a silently empty series.
    func anchoredWorkoutRecords(anchor: HKQueryAnchor?, since: Date?, limit: Int) async throws -> AppleWorkoutPage
}

/// `HKWorkoutActivityType` → the wire's lower snake_case sport.
public enum AppleWorkoutSport {
    public static func name(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "running"
        case .cycling: "cycling"
        case .walking: "walking"
        case .hiking: "hiking"
        case .swimming: "swimming"
        case .rowing: "rowing"
        case .elliptical: "elliptical"
        case .stairClimbing: "stair_climbing"
        case .stairs: "stairs"
        case .stepTraining: "step_training"
        case .traditionalStrengthTraining: "traditional_strength_training"
        case .functionalStrengthTraining: "functional_strength_training"
        case .highIntensityIntervalTraining: "high_intensity_interval_training"
        case .mixedCardio: "mixed_cardio"
        case .coreTraining: "core_training"
        case .crossTraining: "cross_training"
        case .flexibility: "flexibility"
        case .yoga: "yoga"
        case .pilates: "pilates"
        case .cooldown: "cooldown"
        case .dance: "dance"
        case .jumpRope: "jump_rope"
        case .kickboxing: "kickboxing"
        case .boxing: "boxing"
        case .martialArts: "martial_arts"
        case .crossCountrySkiing: "cross_country_skiing"
        case .downhillSkiing: "downhill_skiing"
        case .snowboarding: "snowboarding"
        case .paddleSports: "paddle_sports"
        case .handCycling: "hand_cycling"
        case .skatingSports: "skating_sports"
        case .tennis: "tennis"
        case .soccer: "soccer"
        case .basketball: "basketball"
        case .golf: "golf"
        case .climbing: "climbing"
        case .wheelchairRunPace: "wheelchair_run_pace"
        case .wheelchairWalkPace: "wheelchair_walk_pace"
        case .swimBikeRun: "swim_bike_run"
        case .transition: "transition"
        case .other: "other"
        default: "other_\(type.rawValue)"
        }
    }
}

extension RealHealthStoreReader: HealthStoreWorkoutUploadReading {
    public func anchoredWorkoutRecords(anchor: HKQueryAnchor?, since: Date?, limit: Int) async throws -> AppleWorkoutPage {
        let page = try await anchoredSamples(sampleType: HKWorkoutType.workoutType(), anchor: anchor, since: since, limit: limit)
        let own = HKSource.default().bundleIdentifier
        var records: [AppleWorkoutRecord] = []
        for case let workout as HKWorkout in page.samples {
            let syncId = workout.metadata?[HKMetadataKeySyncIdentifier] as? String
            if AppleWorkoutFilter.isHubBackload(fromThisApp: workout.sourceRevision.source.bundleIdentifier == own, syncIdentifier: syncId) { continue }
            records.append(try await record(for: workout))
        }
        return AppleWorkoutPage(records: records, fetchedCount: page.samples.count, newAnchor: page.newAnchor)
    }

    /// Internal so a hosted test can read one saved workout without the anchor.
    func record(for w: HKWorkout) async throws -> AppleWorkoutRecord {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = w.statistics(for: HKWorkoutUploadTypes.heartRate)
        let activities = w.workoutActivities.map { a in
            AppleWorkoutRecord.Activity(
                uuid: a.uuid, sport: AppleWorkoutSport.name(a.workoutConfiguration.activityType), name: nil,
                start: a.startDate, end: a.endDate ?? w.endDate, durationS: a.duration,
                distanceM: Self.distance { a.statistics(for: $0) })
        }
        var zones: [HAEWorkoutZoneTime]?
        if let group = w.zoneGroup(for: HKWorkoutUploadTypes.heartRate) {
            zones = AppleWorkoutMapper.zoneTimes(group.zoneDurations.map {
                (index: $0.zone.index, lower: $0.zone.minimum?.doubleValue(for: bpm), upper: $0.zone.maximum?.doubleValue(for: bpm), seconds: $0.duration)
            })
        }
        return AppleWorkoutRecord(
            uuid: w.uuid,
            sport: AppleWorkoutSport.name(w.workoutActivityType),
            name: nil,
            isIndoor: (w.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue,
            source: w.sourceRevision.source.name,
            start: w.startDate, end: w.endDate, durationS: w.duration,
            distanceM: Self.distance { w.statistics(for: $0) },
            kcal: w.statistics(for: HKWorkoutUploadTypes.activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            avgHRBpm: hr?.averageQuantity()?.doubleValue(for: bpm),
            maxHRBpm: hr?.maximumQuantity()?.doubleValue(for: bpm),
            effortUser: try await effort(HKWorkoutUploadTypes.workoutEffort, for: w),
            effortEstimated: try await effort(HKWorkoutUploadTypes.estimatedWorkoutEffort, for: w),
            activities: activities,
            hrSamples: try await heartRateSeries(for: w, unit: bpm),
            route: try await routePoints(for: w),
            zoneTime: zones
        )
    }

    private static func distance(_ stats: (HKQuantityType) -> HKStatistics?) -> Double? {
        for type in HKWorkoutUploadTypes.distances {
            if let m = stats(type)?.sumQuantity()?.doubleValue(for: .meter()) { return m }
        }
        return nil
    }

    /// "Nothing stored / not authorized" is an empty answer (rule 5), anything else a failure.
    private static func isEmptyAnswer(_ error: Error) -> Bool {
        guard let code = (error as? HKError)?.code else { return false }
        return code == .errorNoData || code == .errorAuthorizationNotDetermined || code == .errorAuthorizationDenied
    }

    /// The latest effort sample related to the workout (the user may re-rate), 1–10.
    private func effort(_ type: HKQuantityType, for w: HKWorkout) async throws -> Double? {
        let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: w, activity: nil)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { c in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error, !Self.isEmptyAnswer(error) { c.resume(throwing: error) } else { c.resume(returning: samples ?? []) }
            }
            store.execute(q)
        }
        return (samples.first as? HKQuantitySample)?.quantity.doubleValue(for: .appleEffortScore())
    }

    /// Every HR reading inside the workout (series samples expanded), excluding this app's own
    /// writes (the Garmin backload's dense HR would otherwise leak into an Apple workout) unless
    /// they carry the debug-seed marker (`AppleWorkoutFilter.workoutHeartRateSourcePredicate`).
    private func heartRateSeries(for w: HKWorkout, unit: HKUnit) async throws -> [AppleWorkoutRecord.HRSample] {
        let window = AppleWorkoutFilter.workoutHeartRateWindowPredicate(start: w.startDate, end: w.endDate)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window, AppleWorkoutFilter.workoutHeartRateSourcePredicate(
            ownSource: HKQuery.predicateForObjects(from: HKSource.default()))])
        let box = Accumulator<AppleWorkoutRecord.HRSample>()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let q = HKQuantitySeriesSampleQuery(quantityType: HKWorkoutUploadTypes.heartRate, predicate: predicate) { _, quantity, interval, _, done, error in
                if let error {
                    if box.finish() { Self.isEmptyAnswer(error) ? c.resume() : c.resume(throwing: error) }
                    return
                }
                if let quantity, let interval { box.append(.init(ts: interval.start, bpm: quantity.doubleValue(for: unit))) }
                if done, box.finish() { c.resume() }
            }
            store.execute(q)
        }
        return box.items.sorted { $0.ts < $1.ts }
    }

    private func routePoints(for w: HKWorkout) async throws -> [AppleWorkoutRecord.RoutePoint] {
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { c in
            let q = HKSampleQuery(sampleType: HKWorkoutUploadTypes.route, predicate: HKQuery.predicateForObjects(from: w),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error, !Self.isEmptyAnswer(error) { c.resume(throwing: error) }
                else { c.resume(returning: (samples ?? []).compactMap { $0 as? HKWorkoutRoute }) }
            }
            store.execute(q)
        }
        var points: [AppleWorkoutRecord.RoutePoint] = []
        for route in routes {
            let box = Accumulator<AppleWorkoutRecord.RoutePoint>()
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                let q = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if let error {
                        if box.finish() { Self.isEmptyAnswer(error) ? c.resume() : c.resume(throwing: error) }
                        return
                    }
                    for l in locations ?? [] {
                        box.append(.init(ts: l.timestamp, lat: l.coordinate.latitude, lon: l.coordinate.longitude,
                                         elevationM: l.verticalAccuracy >= 0 ? l.altitude : nil,
                                         speedMps: l.speed >= 0 ? l.speed : nil,
                                         hAccuracyM: l.horizontalAccuracy >= 0 ? l.horizontalAccuracy : nil))
                    }
                    if done, box.finish() { c.resume() }
                }
                store.execute(q)
            }
            points += box.items
        }
        return points.sorted { $0.ts < $1.ts }
    }
}

/// Collects values from a HealthKit streaming callback and guards the continuation's single
/// resume. `@unchecked Sendable`: every access goes through `lock`.
private final class Accumulator<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [T] = []
    private var finished = false
    var items: [T] { lock.withLock { _items } }
    func append(_ item: T) { lock.withLock { _items.append(item) } }
    /// True exactly once — the caller that gets it resumes the continuation.
    func finish() -> Bool { lock.withLock { if finished { return false }; finished = true; return true } }
}
#endif

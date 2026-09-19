#if canImport(HealthKit)
import Foundation
import HealthKit

/// Seam over `HKHealthStore` for the READ path — mirrors `HealthStoreWriting`'s style for the
/// write path. `HealthKitUploader` is generic over this so tests inject a fake (HealthKit
/// compiles on macOS, but `HKHealthStore.isHealthDataAvailable()` is always false there, so a
/// real store can never be exercised by `swift test`).
public protocol HealthStoreReading: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization(toRead types: Set<HKObjectType>) async throws
    /// One page of an `HKAnchoredObjectQuery`: samples new/updated since `anchor` (`nil` = from
    /// the beginning), objects deleted since `anchor`, and the anchor to persist for the next
    /// call. Re-running with the same anchor and no new HealthKit data returns an empty page.
    func anchoredSamples(sampleType: HKSampleType, anchor: HKQueryAnchor?, limit: Int) async throws -> HKAnchoredPage
    func enableBackgroundDelivery(for type: HKSampleType, frequency: HKUpdateFrequency) async throws
    func disableBackgroundDelivery(for type: HKSampleType) async throws
    /// Registers an `HKObserverQuery` for `type`. `handler` is invoked on every HealthKit-
    /// delivered update (background or foreground) and is handed a `completion` closure the
    /// caller MUST call once it has finished reacting — `HKObserverQuery`'s documented contract;
    /// skipping it stalls further background delivery for that type.
    func startObserving(_ type: HKSampleType, handler: @escaping @Sendable (_ completion: @escaping @Sendable () -> Void) -> Void) -> HKObserverQuery
    func stopObserving(_ query: HKObserverQuery)
    /// W9 L2 (B-30 P2.7): workouts in `[start, end]` written by sources OTHER than this app —
    /// what `WorkoutOverlapPolicy` compares a hub workout against. This app's own workouts are
    /// excluded because the writer force-overwrites them by sync id and must never see itself
    /// as "another source".
    func workouts(start: Date, end: Date) async throws -> [HKWorkout]
}

public struct HKAnchoredPage: Sendable {
    public var samples: [HKSample]
    public var deletedObjectIDs: [UUID]
    public var newAnchor: HKQueryAnchor?
    public init(samples: [HKSample], deletedObjectIDs: [UUID], newAnchor: HKQueryAnchor?) {
        self.samples = samples; self.deletedObjectIDs = deletedObjectIDs; self.newAnchor = newAnchor
    }
}

public final class RealHealthStoreReader: HealthStoreReading, @unchecked Sendable {
    private let store = HKHealthStore()
    public init() {}

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization(toRead types: Set<HKObjectType>) async throws {
        try await store.requestAuthorization(toShare: [], read: types)
    }

    public func anchoredSamples(sampleType: HKSampleType, anchor: HKQueryAnchor?, limit: Int = HKObjectQueryNoLimit) async throws -> HKAnchoredPage {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: sampleType, predicate: nil, anchor: anchor, limit: limit) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let deletedIDs = (deleted ?? []).map { $0.uuid }
                continuation.resume(returning: HKAnchoredPage(samples: samples ?? [], deletedObjectIDs: deletedIDs, newAnchor: newAnchor))
            }
            store.execute(query)
        }
    }

    public func enableBackgroundDelivery(for type: HKSampleType, frequency: HKUpdateFrequency) async throws {
        try await store.enableBackgroundDelivery(for: type, frequency: frequency)
    }

    public func disableBackgroundDelivery(for type: HKSampleType) async throws {
        try await store.disableBackgroundDelivery(for: type)
    }

    public func startObserving(_ type: HKSampleType, handler: @escaping @Sendable (_ completion: @escaping @Sendable () -> Void) -> Void) -> HKObserverQuery {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
            handler({ completionHandler() })
        }
        store.execute(query)
        return query
    }

    public func stopObserving(_ query: HKObserverQuery) {
        store.stop(query)
    }

    public func workouts(start: Date, end: Date) async throws -> [HKWorkout] {
        let inWindow = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let notOurs = NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [inWindow, notOurs])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKWorkoutType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (samples ?? []).compactMap { $0 as? HKWorkout }) }
            }
            store.execute(query)
        }
    }
}
#endif

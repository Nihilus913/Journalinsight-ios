#if canImport(HealthKit)
import Foundation
import HealthKit

/// Seam over `HKHealthStore` — `HealthKitBackloader` is generic over this so tests inject a fake
/// (HealthKit compiles on macOS, but `HKHealthStore.isHealthDataAvailable()` is always false
/// there, so a real store can never be exercised by `swift test`).
public protocol HealthStoreWriting: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization(toShare types: Set<HKSampleType>) async throws
    /// Sync id -> stored `HKMetadataKeySyncVersion` for every `sampleType` object within
    /// `[start, end]` that carries an `HKMetadataKeySyncIdentifier` (0 when the object has no
    /// version). v4: the runner skips a write only when the stored version is at least the hub's,
    /// so a corrected hub row replaces the sample already in Health.
    func existingSyncVersions(sampleType: HKSampleType, start: Date, end: Date) async throws -> [String: Int]
    func save(_ objects: [HKObject]) async throws
    /// Deletes every `sampleType` object whose `HKMetadataKeySyncIdentifier` is in
    /// `syncIdentifiers` — used to remove a v1 marker (generic `asleep` block, daily `steps`
    /// sample) a v2 write supersedes. A no-op for an empty set.
    func deleteObjects(sampleType: HKSampleType, syncIdentifiers: Set<String>) async throws
    /// Deletes every `sampleType` object in `[start, end]` that `shouldDelete` accepts, returning
    /// how many went. v4's one-time upgrade pass needs this because the objects writer v3 left
    /// behind (all-zero step buckets, negative respiratory-rate sentinels, Garmin RMSSD filed as
    /// SDNN) are identified by their value and sync-id shape, not by a known id set.
    @discardableResult
    func deleteObjects(sampleType: HKSampleType, start: Date, end: Date, where shouldDelete: @Sendable (HKSample) -> Bool) async throws -> Int
    /// Associates already-built samples (active energy, distance) with a saved workout — what
    /// makes Fitness credit the Move ring / Exercise minutes for a third-party workout.
    func add(_ samples: [HKSample], to workout: HKWorkout) async throws
}

public final class RealHealthStore: HealthStoreWriting, @unchecked Sendable {
    private let store = HKHealthStore()
    public init() {}

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
        try await store.requestAuthorization(toShare: types, read: [])
    }

    public func existingSyncVersions(sampleType: HKSampleType, start: Date, end: Date) async throws -> [String: Int] {
        let samples = try await query(sampleType: sampleType, start: start, end: end)
        var out: [String: Int] = [:]
        for sample in samples {
            guard let id = sample.metadata?[HKMetadataKeySyncIdentifier] as? String else { continue }
            let version = (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue ?? 0
            // Several objects can share a sync id across a chunk boundary; keep the highest.
            out[id] = max(out[id] ?? 0, version)
        }
        return out
    }

    private func query(sampleType: HKSampleType, start: Date, end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    public func save(_ objects: [HKObject]) async throws {
        try await store.save(objects)
    }

    public func deleteObjects(sampleType: HKSampleType, syncIdentifiers: Set<String>) async throws {
        guard !syncIdentifiers.isEmpty else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: Array(syncIdentifiers))
        _ = try await store.deleteObjects(of: sampleType, predicate: predicate)
    }

    @discardableResult
    public func deleteObjects(sampleType: HKSampleType, start: Date, end: Date, where shouldDelete: @Sendable (HKSample) -> Bool) async throws -> Int {
        // Filtered in Swift rather than by predicate: the upgrade pass's criteria (a sync-id
        // shape, a value <= 0) have no HKQuery equivalent.
        let doomed = try await query(sampleType: sampleType, start: start, end: end).filter(shouldDelete)
        guard !doomed.isEmpty else { return 0 }
        try await store.delete(doomed)
        return doomed.count
    }

    public func add(_ samples: [HKSample], to workout: HKWorkout) async throws {
        guard !samples.isEmpty else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.add(samples, to: workout) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }
}
#endif

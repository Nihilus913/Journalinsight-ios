#if canImport(HealthKit)
import Foundation
import HealthKit

/// Seam over `HKHealthStore` — `HealthKitBackloader` is generic over this so tests inject a fake
/// (HealthKit compiles on macOS, but `HKHealthStore.isHealthDataAvailable()` is always false
/// there, so a real store can never be exercised by `swift test`).
public protocol HealthStoreWriting: Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization(toShare types: Set<HKSampleType>) async throws
    /// Sync ids already present for `sampleType` within `[start, end]`, read from each sample's
    /// `HKMetadataKeySyncIdentifier` — the idempotency check the runner filters new writes against.
    func existingSyncIds(sampleType: HKSampleType, start: Date, end: Date) async throws -> Set<String>
    func save(_ objects: [HKObject]) async throws
}

public final class RealHealthStore: HealthStoreWriting, @unchecked Sendable {
    private let store = HKHealthStore()
    public init() {}

    public var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
        try await store.requestAuthorization(toShare: types, read: [])
    }

    public func existingSyncIds(sampleType: HKSampleType, start: Date, end: Date) async throws -> Set<String> {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let ids = Set((samples ?? []).compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String })
                continuation.resume(returning: ids)
            }
            store.execute(query)
        }
    }

    public func save(_ objects: [HKObject]) async throws {
        try await store.save(objects)
    }
}
#endif

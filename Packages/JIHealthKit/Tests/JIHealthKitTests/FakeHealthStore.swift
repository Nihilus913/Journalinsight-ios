#if canImport(HealthKit)
import Foundation
import HealthKit
@testable import JIHealthKit

final class FakeHealthStore: HealthStoreWriting, @unchecked Sendable {
    var isHealthDataAvailable: Bool = true
    var authorizationError: Error?
    private(set) var authorizationRequested = false
    private(set) var savedObjects: [HKObject] = []
    /// Pre-seeded "already in HealthKit" sync ids, keyed by `HKSampleType.identifier`.
    var existing: [String: Set<String>] = [:]
    /// Sync ids `deleteObjects` was asked to remove, keyed by `HKSampleType.identifier`.
    private(set) var deletedSyncIds: [String: Set<String>] = [:]

    func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
        authorizationRequested = true
        if let authorizationError { throw authorizationError }
    }

    func existingSyncIds(sampleType: HKSampleType, start: Date, end: Date) async throws -> Set<String> {
        existing[sampleType.identifier] ?? []
    }

    func save(_ objects: [HKObject]) async throws {
        savedObjects.append(contentsOf: objects)
    }

    func deleteObjects(sampleType: HKSampleType, syncIdentifiers: Set<String>) async throws {
        guard !syncIdentifiers.isEmpty else { return }
        deletedSyncIds[sampleType.identifier, default: []].formUnion(syncIdentifiers)
        // Also drop them from `savedObjects` and `existing`, matching a real store's behavior,
        // so a test asserting "written 0 second time" after a delete+rewrite stays meaningful.
        savedObjects.removeAll { ($0.metadata?[HKMetadataKeySyncIdentifier] as? String).map(syncIdentifiers.contains) == true }
        existing[sampleType.identifier]?.subtract(syncIdentifiers)
    }
}
#endif

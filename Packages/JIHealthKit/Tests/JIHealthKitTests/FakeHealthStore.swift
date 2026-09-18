#if canImport(HealthKit)
import Foundation
import HealthKit
@testable import JIHealthKit

final class FakeHealthStore: HealthStoreWriting, @unchecked Sendable {
    var isHealthDataAvailable: Bool = true
    var authorizationError: Error?
    private(set) var authorizationRequested = false
    private(set) var savedObjects: [HKObject] = []
    /// workout sync id -> samples attached via `add(_:to:)`
    private(set) var associated: [String: [HKSample]] = [:]
    /// Pre-seeded "already in HealthKit" sync ids, keyed by `HKSampleType.identifier`. Pre-v4
    /// shorthand: these read back at `HKMetadataKeySyncVersion` 2 (what writer v2/v3 wrote).
    var existing: [String: Set<String>] = [:]
    /// v4: pre-seeded sync id -> stored sync version, keyed by `HKSampleType.identifier`. Merged
    /// over `existing` so a test can pin an exact version without abandoning the old seam.
    var existingVersions: [String: [String: Int]] = [:]
    /// v4: whole samples already in the store, which the `where`-predicate delete is evaluated
    /// against (the upgrade pass filters on value + sync id, not on a known id set).
    var preexisting: [HKSample] = []
    /// Sync ids `deleteObjects` was asked to remove, keyed by `HKSampleType.identifier`.
    private(set) var deletedSyncIds: [String: Set<String>] = [:]
    /// How many times the `where`-predicate delete was invoked — the upgrade pass must not run
    /// again once the stored writer version is current.
    private(set) var whereDeleteCalls = 0

    func requestAuthorization(toShare types: Set<HKSampleType>) async throws {
        authorizationRequested = true
        if let authorizationError { throw authorizationError }
    }

    func existingSyncVersions(sampleType: HKSampleType, start: Date, end: Date) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        for id in existing[sampleType.identifier] ?? [] { out[id] = 2 }
        for (id, version) in existingVersions[sampleType.identifier] ?? [:] { out[id] = version }
        return out
    }

    func save(_ objects: [HKObject]) async throws {
        savedObjects.append(contentsOf: objects)
    }

    func add(_ samples: [HKSample], to workout: HKWorkout) async throws {
        let id = workout.metadata?[HKMetadataKeySyncIdentifier] as? String ?? "?"
        associated[id, default: []].append(contentsOf: samples)
    }

    func deleteObjects(sampleType: HKSampleType, syncIdentifiers: Set<String>) async throws {
        guard !syncIdentifiers.isEmpty else { return }
        record(sampleType: sampleType, ids: syncIdentifiers)
    }

    func deleteObjects(sampleType: HKSampleType, start: Date, end: Date, where shouldDelete: @Sendable (HKSample) -> Bool) async throws -> Int {
        whereDeleteCalls += 1
        let matches = preexisting.filter { $0.sampleType == sampleType && shouldDelete($0) }
        guard !matches.isEmpty else { return 0 }
        preexisting.removeAll { match in matches.contains { $0 === match } }
        record(sampleType: sampleType, ids: Set(matches.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }))
        return matches.count
    }

    /// Mirrors a real store: the ids are gone from `savedObjects`, `existing` and `existingVersions`
    /// afterwards, so a test asserting "written 0 the second time" after a delete+rewrite stays
    /// meaningful.
    private func record(sampleType: HKSampleType, ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deletedSyncIds[sampleType.identifier, default: []].formUnion(ids)
        savedObjects.removeAll { ($0.metadata?[HKMetadataKeySyncIdentifier] as? String).map(ids.contains) == true }
        existing[sampleType.identifier]?.subtract(ids)
        for id in ids {
            existingVersions[sampleType.identifier]?[id] = nil
            associated[id] = nil
        }
    }
}
#endif

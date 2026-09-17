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
}
#endif

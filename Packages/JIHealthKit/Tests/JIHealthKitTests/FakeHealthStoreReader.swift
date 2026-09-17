#if canImport(HealthKit)
import Foundation
import HealthKit
@testable import JIHealthKit

/// Test double for `HealthStoreReading`. `@unchecked Sendable`: mutated only from the serial test
/// runner, same convention as `FakeHealthStore` (the write-path fake this mirrors).
final class FakeHealthStoreReader: HealthStoreReading, @unchecked Sendable {
    var isHealthDataAvailable: Bool = true
    private(set) var requestedReadTypes: Set<HKObjectType> = []
    /// Queue of pages to return per sample-type identifier, in call order. Test setup pushes via
    /// `enqueue`; a type with an empty/missing queue returns an empty page (anchor echoed back).
    private var pages: [String: [HKAnchoredPage]] = [:]
    private(set) var anchorsSeen: [String: [HKQueryAnchor?]] = [:]
    private(set) var backgroundDeliveryEnabled: [String: HKUpdateFrequency] = [:]
    private(set) var backgroundDeliveryDisabled: Set<String> = []
    private(set) var observedTypes: [String] = []
    /// Captured observer handlers, keyed by sample-type identifier, so a test can simulate an
    /// HK-delivered update by invoking it directly instead of waiting on a real background push.
    private(set) var observerHandlers: [String: (@Sendable (@escaping @Sendable () -> Void) -> Void)] = [:]

    func enqueue(_ page: HKAnchoredPage, for type: HKSampleType) {
        pages[type.identifier, default: []].append(page)
    }

    func requestAuthorization(toRead types: Set<HKObjectType>) async throws {
        requestedReadTypes = types
    }

    func anchoredSamples(sampleType: HKSampleType, anchor: HKQueryAnchor?, limit: Int) async throws -> HKAnchoredPage {
        anchorsSeen[sampleType.identifier, default: []].append(anchor)
        guard var queue = pages[sampleType.identifier], !queue.isEmpty else {
            return HKAnchoredPage(samples: [], deletedObjectIDs: [], newAnchor: anchor)
        }
        let page = queue.removeFirst()
        pages[sampleType.identifier] = queue
        return page
    }

    func enableBackgroundDelivery(for type: HKSampleType, frequency: HKUpdateFrequency) async throws {
        backgroundDeliveryEnabled[type.identifier] = frequency
    }

    func disableBackgroundDelivery(for type: HKSampleType) async throws {
        backgroundDeliveryDisabled.insert(type.identifier)
    }

    func startObserving(_ type: HKSampleType, handler: @escaping @Sendable (_ completion: @escaping @Sendable () -> Void) -> Void) -> HKObserverQuery {
        observedTypes.append(type.identifier)
        observerHandlers[type.identifier] = handler
        return HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in completion() }
    }

    func stopObserving(_ query: HKObserverQuery) {}
}
#endif

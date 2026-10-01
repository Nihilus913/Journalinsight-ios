#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

// W-FIX11 H2-03 (bug hunt 2026-10-01): Backload after "Don't Allow" stayed on "Requesting Health
// access…" forever — the read request awaited after the share sheet never returned, and a denied
// share was not noticed. Denied access now ends in `.authorizationDenied` within 5 s.

/// A reader whose read request never answers (what HealthKit did after the declined share sheet).
final class HangingReader: HealthStoreReading, @unchecked Sendable {
    var isHealthDataAvailable: Bool { true }
    func requestAuthorization(toRead types: Set<HKObjectType>) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
    func anchoredSamples(sampleType: HKSampleType, anchor: HKQueryAnchor?, since: Date?, limit: Int) async throws -> HKAnchoredPage {
        HKAnchoredPage(samples: [], deletedObjectIDs: [], newAnchor: anchor)
    }
    func enableBackgroundDelivery(for type: HKSampleType, frequency: HKUpdateFrequency) async throws {}
    func disableBackgroundDelivery(for type: HKSampleType) async throws {}
    func startObserving(_ type: HKSampleType, handler: @escaping @Sendable (_ completion: @escaping @Sendable () -> Void) -> Void) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in completion() }
    }
    func stopObserving(_ query: HKObserverQuery) {}
    func workouts(start: Date, end: Date) async throws -> [HKWorkout] { [] }
}

private func backloader(_ store: FakeHealthStore, reader: (any HealthStoreReading)?) -> HealthKitBackloader {
    let hub = BackloadClient(hub: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t")))
    return HealthKitBackloader(hub: hub, store: store, reader: reader, defaults: UserDefaults(suiteName: "fix11.\(UUID())"))
}

@Suite struct Fix11BackloadAuthTests {
    @Test func deniedShareThrowsDenied() async {
        let store = FakeHealthStore(); store.sharingDenied = true
        await #expect(throws: BackloadError.authorizationDenied) { try await backloader(store, reader: nil).authorize() }
    }

    @Test func aReadRequestThatNeverAnswersEndsWithinFiveSeconds() async throws {
        let store = FakeHealthStore()
        let start = Date()
        try await backloader(store, reader: HangingReader()).authorize()
        #expect(Date().timeIntervalSince(start) < 5.5)
    }
}
#endif

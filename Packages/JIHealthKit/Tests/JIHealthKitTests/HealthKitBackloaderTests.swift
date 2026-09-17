#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JIHub
@testable import JIHealthKit

@Suite(.serialized) struct HealthKitBackloaderTests {
    init() { DynamicStubURLProtocol.reset() }

    private var zurich: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        zurich.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func hubClient() -> BackloadClient {
        BackloadClient(hub: HubClient(config: .init(baseURL: URL(string: "http://hub.test:8000")!, token: "t"), session: DynamicStubURLProtocol.session()))
    }
    private func testDefaults() -> UserDefaults {
        UserDefaults(suiteName: "w2h.test.\(UUID().uuidString)")!
    }

    /// Collects `BackloadProgress` from the `@Sendable` progress closure — a plain `var` capture
    /// is a strict-concurrency error there, even though `run` invokes the closure synchronously.
    private final class ProgressCollector: @unchecked Sendable {
        private(set) var events: [BackloadProgress] = []
        func append(_ p: BackloadProgress) { events.append(p) }
    }

    @Test func writesMonthChunksInOrderAndReportsProgress() async throws {
        let store = FakeHealthStore()
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 7, 17))

        let collector = ProgressCollector()
        let summary = try await backloader.run(range) { collector.append($0) }
        let progresses = collector.events

        #expect(DynamicStubURLProtocol.requestedFroms == ["2025-05-27", "2025-06-01", "2025-07-01"])
        #expect(progresses.map(\.monthIndex) == [1, 2, 3])
        #expect(progresses.allSatisfy { $0.monthCount == 3 })
        #expect(progresses.last?.written == 3)
        #expect(summary.written == 3)
        #expect(summary.skipped == 0)
        #expect(summary.failed.isEmpty)
        #expect(store.savedObjects.count == 3)
    }

    @Test func resumesFromPersistedCursorAndSkipsCompletedRange() async throws {
        let store = FakeHealthStore()
        let defaults = testDefaults()
        let range = BackloadRange(from: day(2025, 5, 27), to: day(2025, 7, 17))

        let first = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        _ = try await first.run(range) { _ in }
        #expect(DynamicStubURLProtocol.requestedFroms.count == 3)

        DynamicStubURLProtocol.reset()
        let second = HealthKitBackloader(hub: hubClient(), store: store, defaults: defaults)
        let summary = try await second.run(range) { _ in }

        #expect(DynamicStubURLProtocol.requestedFroms.isEmpty) // cursor already at range.to -> no chunks
        #expect(summary.written == 0)
        #expect(summary.skipped == 0)
    }

    @Test func skipsSamplesTheFakeStoreAlreadyHolds() async throws {
        let store = FakeHealthStore()
        store.existing[HKQuantityType(.stepCount).identifier] = ["steps:2025-06-01"]
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        let range = BackloadRange(from: day(2025, 6, 1), to: day(2025, 6, 30))

        let summary = try await backloader.run(range) { _ in }

        #expect(summary.written == 0)
        #expect(summary.skipped == 1)
        #expect(store.savedObjects.isEmpty)
    }

    @Test func authorizeThrowsWhenHealthDataUnavailable() async {
        let store = FakeHealthStore()
        store.isHealthDataAvailable = false
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        await #expect(throws: BackloadError.healthDataUnavailable) {
            try await backloader.authorize()
        }
    }

    @Test func authorizeMapsStoreErrorToAuthorizationDenied() async {
        struct SomeError: Error {}
        let store = FakeHealthStore()
        store.authorizationError = SomeError()
        let backloader = HealthKitBackloader(hub: hubClient(), store: store, defaults: testDefaults())
        await #expect(throws: BackloadError.authorizationDenied) {
            try await backloader.authorize()
        }
        #expect(store.authorizationRequested)
    }
}
#endif

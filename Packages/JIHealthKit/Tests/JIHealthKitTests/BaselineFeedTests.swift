#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
@testable import JIHealthKit

/// In-memory `NightlyBaselineStoring` (the GRDB `BaselineStore` is adapted to this in the App).
/// Mirrors the real store's contract: `(source, date)` upsert, 120-day prune on write.
final class FakeBaselineStore: NightlyBaselineStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [String: OnDeviceNight] = [:]
    private(set) var recordCalls = 0
    var failWith: Error?

    func record(_ nights: [OnDeviceNight], today: String) throws {
        if let failWith { throw failWith }
        lock.withLock {
            recordCalls += 1
            for n in nights { rows["\(n.source.rawValue)|\(n.date)"] = n }
        }
    }

    func nightly(through: String) throws -> [OnDeviceNight] {
        if let failWith { throw failWith }
        return lock.withLock { rows.values.filter { $0.date <= through }.sorted { ($0.date, $0.source.rawValue) < ($1.date, $1.source.rawValue) } }
    }

    var all: [OnDeviceNight] { lock.withLock { Array(rows.values) } }
}

/// W-ONDEVICE O-6: what reaches the baseline store from HealthKit. Garmin Connect writes copies of
/// Garmin nights into Health; they must never become "Apple" baseline nights (audit 04-F1: 105/115
/// baseline nights were copies).
@Suite struct BaselineFeedTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = zurich; return c }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 6))! }
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func garminBundlesAreRecognisedAndAppleOnesAreNot() {
        #expect(HKSourceFilter.isExcluded(bundleIdentifier: "com.garmin.connect.mobile"))
        #expect(HKSourceFilter.isExcluded(bundleIdentifier: "com.garmin.connect.mobile.watch"))
        #expect(!HKSourceFilter.isExcluded(bundleIdentifier: "com.apple.health.81A4F1B2"))
        #expect(!HKSourceFilter.isExcluded(bundleIdentifier: nil))
    }

    @Test func garminBundleSamplesAreNeverStoredFromATwoSourceHealthStore() async throws {
        let reader = FakeHealthStoreReader()
        let rhrType = HKReadKind.restingHeartRate.sampleType as! HKQuantityType
        let bpm = HKUnit(from: "count/min")
        let apple = HKQuantitySample(type: rhrType, quantity: HKQuantity(unit: bpm, doubleValue: 52), start: at(3, 7), end: at(3, 7))
        let garmin = HKQuantitySample(type: rhrType, quantity: HKQuantity(unit: bpm, doubleValue: 44), start: at(3, 8), end: at(3, 8))
        let garminOnly = HKQuantitySample(type: rhrType, quantity: HKQuantity(unit: bpm, doubleValue: 43), start: at(2, 8), end: at(2, 8))
        reader.enqueue(HKAnchoredPage(samples: [apple, garmin, garminOnly], deletedObjectIDs: [], newAnchor: nil), for: rhrType)
        let bundles: [UUID: String] = [
            apple.uuid: "com.apple.health.watch",
            garmin.uuid: "com.garmin.connect.mobile",
            garminOnly.uuid: "com.garmin.connect.mobile",
        ]
        let store = FakeBaselineStore()
        let fixed = now
        let provider = HealthKitProvider(
            store: reader, calendar: calendar, now: { fixed },
            sourceBundle: { bundles[$0.uuid] }, baseline: store
        )
        let written = try await provider.refreshBaseline(windowDays: 3)
        #expect(written == 1)
        #expect(store.all == [OnDeviceNight(source: .apple, date: "2026-10-03", rhrBpm: 52)])
    }

    @Test func nightsMapFromRecoveryDaysAsAppleAndEmptyDaysAreSkipped() {
        let days = [
            RecoveryDay(date: "2026-10-03", sleepScore: 81, sleepDurationSec: 27_000, rhrBpm: 50, bodyBatteryAvg: nil,
                        readinessScore: nil, acwr: nil, hrvWeeklyAvg: 41, hrvRmssdMs: 38.5),
        ]
        #expect(OnDeviceNight.apple(from: days) == [
            OnDeviceNight(source: .apple, date: "2026-10-03", hrvRmssdMs: 38.5, rhrBpm: 50, sleepDurationSec: 27_000, sleepScore: 81),
        ])
    }

    @Test func refreshWithoutABaselineStoreIsANoOp() async throws {
        let provider = HealthKitProvider(store: FakeHealthStoreReader(), calendar: calendar, now: { [now] in now })
        #expect(try await provider.refreshBaseline(windowDays: 3) == 0)
    }
}
#endif

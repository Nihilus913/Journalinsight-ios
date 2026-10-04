#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
@testable import JIHealthKit

/// W-ONDEVICE O-8 (Toby Q2): a one-time import of the hub's last 120 nights into the baseline store
/// as `garmin`, so a phone that switches to the on-device verdict is not calibrating again.
@Suite struct OnDeviceSeedTests {
    private func hubDays(_ n: Int, through last: String = "2026-10-03") -> [RecoveryDay] {
        (0..<n).map { i in
            RecoveryDay(date: OnDeviceSeed.addDays(-(n - 1 - i), to: last)!, sleepScore: 78, sleepDurationSec: 26_000, rhrBpm: 49,
                        bodyBatteryAvg: 60, readinessScore: 70, acwr: 1.0, hrvWeeklyAvg: 44, hrvRmssdMs: 45)
        }
    }

    @Test func seedsTheHubSeriesAsGarminNights() async throws {
        let store = FakeBaselineStore()
        let asked = LockedBox<Int?>(nil)
        let outcome = try await OnDeviceSeed.run(hub: { days in asked.value = days; return hubDays(120) }, store: store, today: "2026-10-04")
        #expect(outcome == .seeded(120))
        #expect(asked.value == OnDeviceSeed.days)
        #expect(store.all.count == 120)
        #expect(store.all.allSatisfy { $0.source == .garmin })
        let night = try #require(store.all.first { $0.date == "2026-10-03" })
        #expect(night == OnDeviceNight(source: .garmin, date: "2026-10-03", hrvRmssdMs: 45, rhrBpm: 49, sleepDurationSec: 26_000, sleepScore: 78))
    }

    @Test func seedingTwiceIsIdempotent() async throws {
        let store = FakeBaselineStore()
        _ = try await OnDeviceSeed.run(hub: { _ in hubDays(120) }, store: store, today: "2026-10-04")
        let calls = LockedBox(0)
        let second = try await OnDeviceSeed.run(hub: { _ in calls.value += 1; return hubDays(120) }, store: store, today: "2026-10-04")
        #expect(second == .alreadySeeded)
        #expect(calls.value == 0)
        #expect(store.all.count == 120)
    }

    @Test func skippedWhenThereIsNoHub() async throws {
        let store = FakeBaselineStore()
        #expect(try await OnDeviceSeed.run(hub: nil, store: store, today: "2026-10-04") == .noHub)
        #expect(store.all.isEmpty)
    }

    @Test func todayAndFutureHubRowsAreNotSeeded() async throws {
        let store = FakeBaselineStore()
        let outcome = try await OnDeviceSeed.run(hub: { _ in hubDays(3, through: "2026-10-05") }, store: store, today: "2026-10-04")
        // Tonight is the phone's own Apple night, never a hub copy.
        #expect(outcome == .seeded(1))
        #expect(store.all.map(\.date) == ["2026-10-03"])
    }

    @Test func seededPhoneIsNotCalibrating() async throws {
        guard HKReadKind.hrvRMSSDTypeAvailable else { return }
        let zurich = TimeZone(identifier: "Europe/Zurich")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zurich
        func at(_ d: Int, _ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }
        let reader = FakeHealthStoreReader()
        let sleepType = try #require(HKReadKind.sleepAnalysis.sampleType)
        reader.enqueue(HKAnchoredPage(samples: [
            HKCategorySample(type: sleepType as! HKCategoryType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: at(3, 22), end: at(4, 5)),
        ], deletedObjectIDs: [], newAnchor: nil), for: sleepType)
        let rmssdType = try #require(HKReadKind.hrvRMSSDQuantityType)
        reader.enqueue(HKAnchoredPage(samples: [
            HKQuantitySample(type: rmssdType, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 41), start: at(4, 2), end: at(4, 2)),
        ], deletedObjectIDs: [], newAnchor: nil), for: rmssdType)
        let store = FakeBaselineStore()
        _ = try await OnDeviceSeed.run(hub: { _ in hubDays(120) }, store: store, today: "2026-10-04")
        let fixed = at(4, 6)
        let p = HealthKitProvider(store: reader, calendar: cal, now: { fixed }, sourceBundle: { _ in nil },
                                  baseline: store, onDevice: StubVerdictCompute())
        let v = try await p.morningVerdict(date: "2026-10-04")
        #expect(v.reason == "HRV in band")
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
#endif

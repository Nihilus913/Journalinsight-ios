#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JICompute
@testable import JIHealthKit

/// RG-04 / B-120: the phone's on-device verdict for 2026-10-05 read "2 Apple + 0 Garmin nights
/// (2/28), only 5.0 h sleep" while the hub read 28 nights and 7.3 h for the same night.
/// Causes: (1) each sleep sample was bucketed by its OWN end day, so the part of the night before
/// midnight landed on the previous day (7.3 h -> ~5 h); (2) a cold baseline store was only ever
/// refreshed 3 days back; (3) no Garmin nights completed the 28-night baseline as the hub does.
@Suite struct B120NightInputsTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = zurich; return c }
    /// 2026-10-05 06:00 local.
    private var now: Date { at(10, 5, 6) }
    private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }
    private func sleep(_ from: Date, _ to: Date) -> HKCategorySample {
        HKCategorySample(type: HKReadKind.sleepAnalysis.sampleType as! HKCategoryType,
                         value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: from, end: to)
    }

    /// The real night of 2026-10-04 -> 10-05 (import.apple_sleep_segment): 26 400 s asleep.
    private var realNight: [HKCategorySample] {
        [sleep(at(10, 4, 21, 13, 41), at(10, 4, 22, 45, 5)),
         sleep(at(10, 4, 22, 46, 35), at(10, 4, 22, 48, 5)),
         sleep(at(10, 4, 23, 2, 34), at(10, 5, 1, 26, 54)),
         sleep(at(10, 5, 1, 30, 54), at(10, 5, 4, 38, 41)),
         sleep(at(10, 5, 4, 40, 11), at(10, 5, 4, 42, 41)),
         sleep(at(10, 5, 4, 46, 41), at(10, 5, 4, 59, 10))]
    }

    @Test func aNightCrossingMidnightCountsWholeOnItsWakeDay() {
        let window = HKSampleWindow(windowDays: 3, now: now, calendar: calendar)
        let nights = HKSleepAssembler.nights(from: realNight, window: window)
        #expect(nights["2026-10-05"]?.durationSec == 26_400)
        #expect(nights["2026-10-04"] == nil)   // the evening part is not a 10-04 night
    }

    /// 16 prior Apple nights (09-19 … 10-04) + tonight in HealthKit; the hub's Garmin nights
    /// (recovery-inputs, `hrv_src` garmin, already x0.95) before the Watch.
    private func seedHealthKit(_ reader: FakeHealthStoreReader) throws {
        var sleepSamples = realNight
        var hrv: [HKSample] = []
        guard let rmssdType = HKReadKind.hrvRMSSDQuantityType else { return }
        let ms = HKUnit.secondUnit(with: .milli)
        for offset in 1...16 {   // 10-04 back to 09-19
            let wake = calendar.date(byAdding: .day, value: -offset, to: at(10, 5, 5))!
            sleepSamples.append(sleep(wake.addingTimeInterval(-7 * 3600), wake))
            hrv.append(HKQuantitySample(type: rmssdType, quantity: HKQuantity(unit: ms, doubleValue: 20 + Double(offset % 6)),
                                        start: wake.addingTimeInterval(-3 * 3600), end: wake.addingTimeInterval(-3 * 3600)))
        }
        hrv.append(HKQuantitySample(type: rmssdType, quantity: HKQuantity(unit: ms, doubleValue: 25.88),
                                    start: at(10, 5, 2), end: at(10, 5, 2)))
        let sleepType = try #require(HKReadKind.sleepAnalysis.sampleType)
        reader.enqueue(HKAnchoredPage(samples: sleepSamples, deletedObjectIDs: [], newAnchor: nil), for: sleepType)
        reader.enqueue(HKAnchoredPage(samples: hrv, deletedObjectIDs: [], newAnchor: nil), for: rmssdType)
    }

    private var hubGarminDays: [RecoveryInputDay] {
        (1...19).map { i in   // 08-25 … 09-12
            let d = calendar.date(byAdding: .day, value: i - 1, to: at(8, 25, 12))!
            return RecoveryInputDay(date: HKSampleWindow.isoDay(d, calendar: calendar), hrvMs: 26.6, rhrBpm: 50, sleepH: 7.2, hrvSrc: "garmin")
        } + [RecoveryInputDay(date: "2026-09-19", hrvMs: 21.66, sleepH: 6.58, hrvSrc: "apple"),
             RecoveryInputDay(date: "2026-09-13", sleepH: 8.8)]
    }

    @Test func seedTakesOnlyTheHubsGarminNightsUnscaled() async throws {
        let store = FakeBaselineStore()
        let outcome = try await OnDeviceSeed.runGarmin(hub: { _ in hubGarminDays }, store: store, today: "2026-10-05")
        #expect(outcome == .seeded(19))
        let nights = try store.nightly(through: "2026-10-05")
        #expect(nights.allSatisfy { $0.source == .garmin })
        #expect(nights.first?.hrvRmssdMs == 28)   // 26.6 / 0.95 — the engine scales it once
        #expect(try await OnDeviceSeed.runGarmin(hub: { _ in hubGarminDays }, store: store, today: "2026-10-05") == .alreadySeeded)
    }

    @Test func coldStoreReadsTheSame28NightsAndSleepAsTheHub() async throws {
        try #require(HKReadKind.hrvRMSSDTypeAvailable)
        let reader = FakeHealthStoreReader()
        try seedHealthKit(reader)
        let store = FakeBaselineStore()
        _ = try await OnDeviceSeed.runGarmin(hub: { _ in hubGarminDays }, store: store, today: "2026-10-05")
        let fixed = now
        let p = HealthKitProvider(store: reader, calendar: calendar, now: { fixed }, sourceBundle: { _ in nil },
                                  baseline: store, onDevice: JIComputeVerdictEngine())
        let r = try #require(try await p.onDeviceVerdict(day: "2026-10-05"))
        #expect(r.baselineNights == 28)
        #expect(r.signals.first { $0.key == "sleep_h" }?.value == 7.3)
        #expect(!(r.reason ?? "").contains("calibrating"))
        // One 120-day read, not the 3-day refresh, on a cold store.
        let since = try #require(reader.sinceSeen[HKReadKind.sleepAnalysis.sampleType!.identifier]?.first ?? nil)
        #expect(now.timeIntervalSince(since) > 100 * 86_400)
    }
}
#endif

#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
import JICore
import JICompute
@testable import JIHealthKit

/// W7-L3 (P-healthkit-t2-provider). Every test drives the real `HealthKitProvider` against
/// `FakeHealthStoreReader` — HealthKit itself is never reachable under `swift test`
/// (`HKHealthStore.isHealthDataAvailable()` is always false on macOS), so the seeded fake IS the
/// device here.
@Suite struct HealthKitProviderTests {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zurich
        return c
    }
    /// 2026-09-18 10:00 local — the "now" every window in this suite is anchored on.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 10))! }

    private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func quantity(_ kind: HKReadKind, _ value: Double, unit: HKUnit, at start: Date) -> HKQuantitySample {
        HKQuantitySample(type: kind.sampleType as! HKQuantityType, quantity: HKQuantity(unit: unit, doubleValue: value), start: start, end: start)
    }

    private func sleep(_ value: HKCategoryValueSleepAnalysis, from: Date, to: Date) -> HKCategorySample {
        HKCategorySample(type: HKReadKind.sleepAnalysis.sampleType as! HKCategoryType, value: value.rawValue, start: from, end: to)
    }

    private func seed(_ store: FakeHealthStoreReader, kind: HKReadKind, _ samples: [HKSample]) {
        guard let type = kind.sampleType else { return }
        store.enqueue(HKAnchoredPage(samples: samples, deletedObjectIDs: [], newAnchor: nil), for: type)
    }

    private func provider(
        _ store: FakeHealthStoreReader,
        capabilities: DataCapability = .appleWatchCapabilities
    ) -> HealthKitProvider {
        let fixed = now
        return HealthKitProvider(store: store, capabilities: capabilities, calendar: calendar, now: { fixed })
    }

    // MARK: - Sleep score comes from JICompute, bit-exact

    /// The exit criterion: a fake-store-seeded window produces the score `JICompute` computes for
    /// the same totals. The expectation is derived by calling `computeSleepScore` directly here,
    /// so any drift between this package and the W6 parity port fails the test rather than
    /// quietly shipping a second implementation.
    @Test func recoverySleepScoreMatchesJIComputeBitExact() async throws {
        let store = FakeHealthStoreReader()
        // One night ending the morning of 2026-09-18: deep 1 h, REM 1 h 30, core 5 h, awake 30 min.
        seed(store, kind: .sleepAnalysis, [
            sleep(.asleepDeep, from: at(9, 17, 23), to: at(9, 18, 0)),
            sleep(.asleepREM, from: at(9, 18, 0), to: at(9, 18, 1, 30)),
            sleep(.asleepCore, from: at(9, 18, 1, 30), to: at(9, 18, 6, 30)),
            sleep(.awake, from: at(9, 18, 6, 30), to: at(9, 18, 7)),
        ])
        let days = try await provider(store).recovery(windowDays: 3)
        let day = try #require(days.first { $0.date == "2026-09-18" })

        let expected = try #require(computeSleepScore(durationSec: 27_000, deepSec: 3_600, remSec: 5_400, awakeSec: 1_800))
        #expect(day.sleepScore == Double(expected))
        #expect(day.sleepDurationSec == 27_000)
    }

    /// A night with no stage breakdown must report `nil` stages, not zeros: `computeSleepScore`
    /// scores a missing stage at 80% of its weight and a present-zero stage at 0%, so collapsing
    /// the two would make every unstaged Apple night look far worse than it was.
    @Test func unstagedNightReportsMissingStagesRatherThanZeros() async throws {
        let store = FakeHealthStoreReader()
        seed(store, kind: .sleepAnalysis, [
            sleep(.asleepUnspecified, from: at(9, 17, 23), to: at(9, 18, 6)),
        ])
        let days = try await provider(store).recovery(windowDays: 3)
        let day = try #require(days.first { $0.date == "2026-09-18" })

        let expected = try #require(computeSleepScore(durationSec: 25_200, deepSec: nil, remSec: nil, awakeSec: nil))
        #expect(day.sleepScore == Double(expected))
        // Not the same as the all-zero-stage reading — proves the nil/zero distinction survives.
        let zeroed = try #require(computeSleepScore(durationSec: 25_200, deepSec: 0, remSec: 0, awakeSec: 0))
        #expect(expected != zeroed)
    }

    @Test func nightsAreBucketedByTheDayTheyEndOn() {
        let window = HKSampleWindow(windowDays: 3, now: now, calendar: calendar)
        let nights = HKSleepAssembler.nights(from: [
            sleep(.asleepCore, from: at(9, 16, 23), to: at(9, 17, 6)),
            sleep(.asleepCore, from: at(9, 17, 23), to: at(9, 18, 5)),
        ], window: window)
        #expect(Set(nights.keys) == ["2026-09-17", "2026-09-18"])
        #expect(nights["2026-09-17"]?.durationSec == 25_200)
        #expect(nights["2026-09-18"]?.durationSec == 21_600)
    }

    @Test func aDayOfOnlyAwakeSamplesHasNoNightToScore() {
        let window = HKSampleWindow(windowDays: 3, now: now, calendar: calendar)
        let nights = HKSleepAssembler.nights(from: [
            sleep(.awake, from: at(9, 18, 3), to: at(9, 18, 4)),
            sleep(.inBed, from: at(9, 18, 1), to: at(9, 18, 7)),
        ], window: window)
        #expect(nights.isEmpty)
    }

    // MARK: - Resting HR / HRV

    @Test func restingHeartRateIsTheDailyMean() async throws {
        let store = FakeHealthStoreReader()
        let bpm = HKUnit(from: "count/min")
        seed(store, kind: .restingHeartRate, [
            quantity(.restingHeartRate, 50, unit: bpm, at: at(9, 18, 6)),
            quantity(.restingHeartRate, 56, unit: bpm, at: at(9, 18, 8)),
            quantity(.restingHeartRate, 61, unit: bpm, at: at(9, 17, 7)),
        ])
        let days = try await provider(store).recovery(windowDays: 3)
        #expect(days.first { $0.date == "2026-09-18" }?.rhrBpm == 53)
        #expect(days.first { $0.date == "2026-09-17" }?.rhrBpm == 61)
    }

    @Test func hrvWeeklyAverageIsATrailingMeanOverTheDaysPresent() async throws {
        let store = FakeHealthStoreReader()
        let ms = HKUnit.secondUnit(with: .milli)
        let kind = try #require(provider(store).hrvKind)
        seed(store, kind: kind, [
            quantity(kind, 40, unit: ms, at: at(9, 17, 4)),
            quantity(kind, 60, unit: ms, at: at(9, 18, 4)),
        ])
        let days = try await provider(store).recovery(windowDays: 3)
        #expect(days.first { $0.date == "2026-09-17" }?.hrvWeeklyAvg == 40)
        #expect(days.first { $0.date == "2026-09-18" }?.hrvWeeklyAvg == 50)
    }

    /// Native RMSSD (iOS 27) only when the running OS actually exposes the type — otherwise the
    /// query would resolve to `nil` and silently read nothing. The assertion is derived from
    /// `HKReadKind.hrvRMSSDTypeAvailable` so it is meaningful on both host generations.
    @Test func hrvUsesNativeRmssdOnlyWhenTheTypeIsAvailable() async throws {
        let store = FakeHealthStoreReader()
        let p = provider(store, capabilities: [.recovery, .sleepSummary, .hrvRMSSD, .hrvSDNN])
        _ = try await p.recovery(windowDays: 2)
        let queried = Set(store.anchorsSeen.keys)
        if HKReadKind.hrvRMSSDTypeAvailable {
            #expect(p.hrvKind == .hrvRMSSD)
            #expect(queried.contains(try #require(HKReadKind.hrvRMSSD.sampleType).identifier))
        } else {
            #expect(p.hrvKind == .hrvSDNN)
            #expect(queried.contains(try #require(HKReadKind.hrvSDNN.sampleType).identifier))
        }
    }

    @Test func hrvFallsBackToSdnnWithoutTheRmssdCapability() async throws {
        let store = FakeHealthStoreReader()
        let p = provider(store, capabilities: [.recovery, .sleepSummary, .hrvSDNN])
        #expect(p.hrvKind == .hrvSDNN)
        _ = try await p.recovery(windowDays: 2)
        let sdnn = try #require(HKReadKind.hrvSDNN.sampleType).identifier
        #expect(store.anchorsSeen.keys.contains(sdnn))
        if let rmssd = HKReadKind.hrvRMSSD.sampleType {
            #expect(!store.anchorsSeen.keys.contains(rmssd.identifier))
        }
    }

    @Test func noHrvCapabilityMeansNoHrvQueryAndNoFabricatedAverage() async throws {
        let store = FakeHealthStoreReader()
        let p = provider(store, capabilities: [.recovery, .sleepSummary])
        #expect(p.hrvKind == nil)
        seed(store, kind: .sleepAnalysis, [sleep(.asleepCore, from: at(9, 17, 23), to: at(9, 18, 6))])
        let days = try await p.recovery(windowDays: 3)
        #expect(days.allSatisfy { $0.hrvWeeklyAvg == nil })
    }

    // MARK: - What Apple cannot supply stays nil

    @Test func garminOnlyMetricsAreNeverFabricated() async throws {
        let store = FakeHealthStoreReader()
        seed(store, kind: .sleepAnalysis, [sleep(.asleepCore, from: at(9, 17, 23), to: at(9, 18, 6))])
        let days = try await provider(store).recovery(windowDays: 3)
        #expect(!days.isEmpty)
        for day in days {
            #expect(day.bodyBatteryAvg == nil)
            #expect(day.readinessScore == nil)
            #expect(day.acwr == nil)
        }
        let caps = DataCapability.appleWatchCapabilities
        #expect(!caps.contains(.bodyBattery))
        #expect(!caps.contains(.trainingReadiness))
        #expect(!caps.contains(.garminSleepScore))
    }

    @Test func daysWithoutAnySignalAreOmittedRatherThanZeroed() async throws {
        let store = FakeHealthStoreReader()
        seed(store, kind: .sleepAnalysis, [sleep(.asleepCore, from: at(9, 17, 23), to: at(9, 18, 6))])
        let days = try await provider(store).recovery(windowDays: 5)
        #expect(days.map(\.date) == ["2026-09-18"])
    }

    @Test func samplesOutsideTheWindowAreIgnored() async throws {
        let store = FakeHealthStoreReader()
        seed(store, kind: .restingHeartRate, [
            quantity(.restingHeartRate, 52, unit: HKUnit(from: "count/min"), at: at(9, 1, 7)),
        ])
        let days = try await provider(store).recovery(windowDays: 3)
        #expect(days.isEmpty)
    }

    // MARK: - health() / syncStatus()

    @Test func healthReflectsHealthKitAvailability() async throws {
        let store = FakeHealthStoreReader()
        let available = try await provider(store).health()
        #expect(available.status == "ok")
        store.isHealthDataAvailable = false
        let unavailable = try await provider(store).health()
        #expect(unavailable.status == "unavailable")
    }

    @Test func syncStatusIsNilUntilTheFirstAnchoredFetch() async throws {
        let store = FakeHealthStoreReader()
        let p = provider(store)
        let before = try await p.syncStatus()
        #expect(before.lastSync == nil)
        _ = try await p.recovery(windowDays: 2)
        let after = try await p.syncStatus()
        #expect(after.lastSync == now.ISO8601Format())
    }

    @Test func recoveryThrowsWhenHealthKitIsUnavailable() async {
        let store = FakeHealthStoreReader()
        store.isHealthDataAvailable = false
        await #expect(throws: ProviderError.healthDataUnavailable) {
            _ = try await provider(store).recovery(windowDays: 7)
        }
    }
}
#endif

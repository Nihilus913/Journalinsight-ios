#if canImport(HealthKit)
import Foundation
import Testing
import HealthKit
import JICore
@testable import JIHealthKit

/// W9.5 L2: direct coverage for `Provider/HKRecoveryAssembler.swift` — `days()` and `dailyMean()`
/// on empty input, a single day, a gap day, and samples straddling a Zurich midnight (the
/// window's calendar decides the bucket, never the sample's wall clock elsewhere).
@Suite struct HKRecoveryAssemblerTests {
    private var zurich: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }

    /// 2026-09-18 10:00 Zurich.
    private var now: Date { zurich.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 10))! }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        zurich.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private let bpm = HKUnit(from: "count/min")
    private let ms = HKUnit.secondUnit(with: .milli)

    private func rhr(_ value: Double, at start: Date) -> HKQuantitySample {
        HKQuantitySample(type: HKQuantityType(.restingHeartRate), quantity: HKQuantity(unit: bpm, doubleValue: value), start: start, end: start)
    }

    private func hrv(_ value: Double, at start: Date) -> HKQuantitySample {
        HKQuantitySample(type: HKQuantityType(.heartRateVariabilitySDNN), quantity: HKQuantity(unit: ms, doubleValue: value), start: start, end: start)
    }

    private func sleep(from: Date, to: Date) -> HKCategorySample {
        HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: from, end: to)
    }

    // MARK: - days()

    @Test func emptyInputYieldsNoDays() {
        let window = HKSampleWindow(windowDays: 7, now: now, calendar: zurich)
        #expect(HKRecoveryAssembler.days(window: window, restingHeartRate: [], hrv: [], sleep: []).isEmpty)
    }

    @Test func oneDayOfSignalYieldsExactlyThatDayWithGarminOnlyFieldsNil() throws {
        let window = HKSampleWindow(windowDays: 7, now: now, calendar: zurich)
        let days = HKRecoveryAssembler.days(
            window: window,
            restingHeartRate: [rhr(50, at: at(18, 8)), rhr(54, at: at(18, 9))],
            hrv: [hrv(40, at: at(18, 7))],
            sleep: [sleep(from: at(17, 23), to: at(18, 6))])
        let day = try #require(days.first)
        #expect(days.count == 1)
        #expect(day.date == "2026-09-18")
        #expect(day.rhrBpm == 52)
        #expect(day.hrvWeeklyAvg == 40)
        #expect(day.sleepDurationSec == 25_200)
        #expect(day.sleepScore != nil)
        #expect(day.bodyBatteryAvg == nil)
        #expect(day.readinessScore == nil)
        #expect(day.acwr == nil)
    }

    @Test func gapDayWithNoSignalAtAllIsOmitted() {
        let window = HKSampleWindow(windowDays: 3, now: now, calendar: zurich)
        let days = HKRecoveryAssembler.days(
            window: window,
            restingHeartRate: [rhr(50, at: at(16, 8)), rhr(60, at: at(18, 8))],
            hrv: [], sleep: [])
        #expect(days.map(\.date) == ["2026-09-16", "2026-09-18"])
        #expect(days.map(\.rhrBpm) == [50, 60])
        #expect(days.allSatisfy { $0.hrvWeeklyAvg == nil && $0.sleepDurationSec == nil })
    }

    @Test func hrvGapDayStillCarriesTheTrailingMeanOverPresentDaysOnly() {
        let window = HKSampleWindow(windowDays: 3, now: now, calendar: zurich)
        let days = HKRecoveryAssembler.days(
            window: window,
            restingHeartRate: [],
            hrv: [hrv(30, at: at(16, 8)), hrv(50, at: at(18, 8))],
            sleep: [])
        // The 17th has no reading of its own but a trailing mean (30) — it is a row, not a gap.
        #expect(days.map(\.date) == ["2026-09-16", "2026-09-17", "2026-09-18"])
        #expect(days.map(\.hrvWeeklyAvg) == [30, 30, 40]) // 18th = mean(30, 50), never (30 + 0 + 50) / 3
        #expect(days.allSatisfy { $0.rhrBpm == nil })
    }

    @Test func hrvWeeklyAverageWindowIsSevenDaysInclusive() {
        let window = HKSampleWindow(windowDays: 9, now: now, calendar: zurich)
        // 10th..18th: value = day number, so day 18's trailing-7 mean = mean(12...18) = 15.
        let hrvs = (10...18).map { hrv(Double($0), at: at($0, 8)) }
        let days = HKRecoveryAssembler.days(window: window, restingHeartRate: [], hrv: hrvs, sleep: [])
        #expect(days.count == 9)
        #expect(days.last?.hrvWeeklyAvg == 15)
        #expect(days.first?.hrvWeeklyAvg == 10)
    }

    @Test func samplesOutsideTheWindowAreIgnored() {
        let window = HKSampleWindow(windowDays: 2, now: now, calendar: zurich)
        let days = HKRecoveryAssembler.days(
            window: window, restingHeartRate: [rhr(50, at: at(15, 8))], hrv: [hrv(40, at: at(19, 8))], sleep: [])
        #expect(days.isEmpty)
    }

    // MARK: - dailyMean()

    @Test func dailyMeanOfNothingIsEmpty() {
        let window = HKSampleWindow(windowDays: 7, now: now, calendar: zurich)
        #expect(HKRecoveryAssembler.dailyMean([], unit: bpm, window: window).isEmpty)
    }

    @Test func dailyMeanBucketsByZurichMidnightNotUTC() {
        // 2026-09-17 23:30 Zurich (= 21:30 UTC) and 2026-09-18 00:30 Zurich (= 22:30 UTC on the
        // 17th): both are the 17th in UTC, but the window's Zurich calendar splits them.
        let window = HKSampleWindow(windowDays: 3, now: now, calendar: zurich)
        let means = HKRecoveryAssembler.dailyMean(
            [rhr(50, at: at(17, 23, 30)), rhr(70, at: at(18, 0, 30))], unit: bpm, window: window)
        #expect(means == ["2026-09-17": 50, "2026-09-18": 70])
    }

    @Test func aDeviceInAnotherTimeZoneAgreesWithTheZurichBucket() {
        // Same instants; only the window's calendar decides — a Los Angeles device using the
        // Zurich window must produce the same keys.
        let zurichWindow = HKSampleWindow(windowDays: 3, now: now, calendar: zurich)
        let samples = [rhr(50, at: at(17, 23, 30)), rhr(70, at: at(18, 0, 30))]
        let zurichMeans = HKRecoveryAssembler.dailyMean(samples, unit: bpm, window: zurichWindow)
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let laWindow = HKSampleWindow(windowDays: 3, now: now, calendar: la)
        let laMeans = HKRecoveryAssembler.dailyMean(samples, unit: bpm, window: laWindow)
        #expect(zurichMeans.keys.sorted() == ["2026-09-17", "2026-09-18"])
        // LA is 9 h behind: both instants fall on the LA 17th — proof the calendar is the bucket.
        #expect(laMeans == ["2026-09-17": 60])
    }

    @Test func dailyMeanSkipsIncompatibleUnitsAndNonQuantitySamples() {
        let window = HKSampleWindow(windowDays: 3, now: now, calendar: zurich)
        let means = HKRecoveryAssembler.dailyMean(
            [rhr(50, at: at(18, 8)), hrv(40, at: at(18, 8)), sleep(from: at(17, 23), to: at(18, 6))],
            unit: bpm, window: window)
        #expect(means == ["2026-09-18": 50])
    }
}
#endif

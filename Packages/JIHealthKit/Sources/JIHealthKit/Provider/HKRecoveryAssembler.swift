#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore

/// Turns raw HealthKit samples into the hub's `[RecoveryDay]` shape, so every Recovery/Today tile
/// reads the same DTO whether the bytes came from the Mac hub (T1) or from the watch on this
/// device (T2).
///
/// What Apple cannot supply is left `nil`, never zeroed (XC `CLAUDE.md` rule 5):
/// `bodyBatteryAvg`, `readinessScore` and `acwr` are Garmin/Firstbeat-derived — memory
/// `project_source_agnostic_gate` (Apple and Garmin do not align), and `Capabilities+HK` never
/// sets those flags. A day with no signal at all is omitted rather than emitted as an all-`nil`
/// row, matching what the hub returns for a day it has nothing for.
public enum HKRecoveryAssembler {
    /// Number of days averaged into `hrvWeeklyAvg`, including the day itself — the hub's own
    /// weekly HRV window.
    public static let hrvAverageDays = 7

    /// - Parameters:
    ///   - restingHeartRate: `HKQuantitySample`s in `beats/min`.
    ///   - hrv: `HKQuantitySample`s in milliseconds (SDNN or native RMSSD — the provider picks
    ///     which type it read; the arithmetic is identical).
    ///   - sleep: sleep-analysis `HKCategorySample`s, bucketed by `HKSleepAssembler`.
    public static func days(
        window: HKSampleWindow,
        restingHeartRate: [HKSample],
        hrv: [HKSample],
        sleep: [HKSample]
    ) -> [RecoveryDay] {
        let rhrByDay = dailyMean(restingHeartRate, unit: HKUnit(from: "count/min"), window: window)
        let hrvByDay = dailyMean(hrv, unit: .secondUnit(with: .milli), window: window)
        let nights = HKSleepAssembler.nights(from: sleep, window: window)

        var out: [RecoveryDay] = []
        out.reserveCapacity(window.days.count)
        for (index, day) in window.days.enumerated() {
            let night = nights[day]
            let rhr = rhrByDay[day]
            // Trailing mean over the days actually present in the window — a short window (or a
            // gap) averages fewer days rather than reporting a wrong number or a zero.
            let lower = max(0, index - (hrvAverageDays - 1))
            let recent = window.days[lower...index].compactMap { hrvByDay[$0] }
            let weekly = recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
            guard night != nil || rhr != nil || weekly != nil else { continue }
            out.append(RecoveryDay(
                date: day,
                sleepScore: night?.sleepScore.map(Double.init),
                sleepDurationSec: night.map { Double($0.durationSec) },
                rhrBpm: rhr,
                bodyBatteryAvg: nil,
                readinessScore: nil,
                acwr: nil,
                hrvWeeklyAvg: weekly
            ))
        }
        return out
    }

    /// Arithmetic mean of each day's quantity samples, bucketed by the local day of `startDate`
    /// (a resting-HR / HRV reading belongs to the day it was taken, unlike a sleep night).
    static func dailyMean(_ samples: [HKSample], unit: HKUnit, window: HKSampleWindow) -> [String: Double] {
        var sums: [String: (total: Double, count: Int)] = [:]
        for case let sample as HKQuantitySample in samples {
            guard let day = window.dayKey(for: sample.startDate) else { continue }
            guard sample.quantity.is(compatibleWith: unit) else { continue }
            let value = sample.quantity.doubleValue(for: unit)
            let existing = sums[day] ?? (0, 0)
            sums[day] = (existing.total + value, existing.count + 1)
        }
        return sums.mapValues { $0.total / Double($0.count) }
    }
}
#endif

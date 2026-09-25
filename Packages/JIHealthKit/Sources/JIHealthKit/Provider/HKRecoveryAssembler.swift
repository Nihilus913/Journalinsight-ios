#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore

/// Turns raw HealthKit samples into the hub's `[RecoveryDay]` shape, so every Recovery/Today tile
/// reads the same DTO whether the bytes came from the Mac hub (T1) or from the watch on this
/// device (T2).
///
/// `hrvRmssdMs` is the night's own native RMSSD (W-FIX3 C-h), dated to the wake-up day.
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
        let rmssdByNight = nightlyRmssd(hrv, window: window)

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
            let rmssd = rmssdByNight[day]
            guard night != nil || rhr != nil || weekly != nil || rmssd != nil else { continue }
            out.append(RecoveryDay(
                date: day,
                sleepScore: night?.sleepScore.map(Double.init),
                sleepDurationSec: night.map { Double($0.durationSec) },
                rhrBpm: rhr,
                bodyBatteryAvg: nil,
                readinessScore: nil,
                acwr: nil,
                hrvWeeklyAvg: weekly,
                hrvRmssdMs: rmssd
            ))
        }
        return out
    }

    /// Local hour from which an RMSSD reading counts toward the NEXT day's night.
    static let nightStartHour = 18

    /// W-FIX3 C-h: that night's own RMSSD (`RecoveryDay.hrvRmssdMs`, the hub's `hrv_rmssd_ms`).
    /// Only native RMSSD samples count — SDNN is a different statistic and never stands in (rule 5:
    /// no invented values; a day without RMSSD stays `nil`, never 0). A reading is dated to the
    /// morning you wake up, like `HKSleepAssembler`'s nights: from `nightStartHour` local it
    /// belongs to the next day, so 23:30 and 03:00 readings land on the same night.
    static func nightlyRmssd(_ samples: [HKSample], window: HKSampleWindow) -> [String: Double] {
        guard let rmssdType = HKReadKind.hrvRMSSDQuantityType else { return [:] }
        let unit = HKUnit.secondUnit(with: .milli)
        let cal = window.calendar
        var sums: [String: (total: Double, count: Int)] = [:]
        for case let sample as HKQuantitySample in samples where sample.quantityType == rmssdType {
            guard sample.quantity.is(compatibleWith: unit) else { continue }
            let hour = cal.component(.hour, from: sample.startDate)
            let nightOf = hour >= nightStartHour
                ? (cal.date(byAdding: .day, value: 1, to: sample.startDate) ?? sample.startDate)
                : sample.startDate
            guard let day = window.dayKey(for: nightOf) else { continue }
            let existing = sums[day] ?? (0, 0)
            sums[day] = (existing.total + sample.quantity.doubleValue(for: unit), existing.count + 1)
        }
        return sums.mapValues { $0.total / Double($0.count) }
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

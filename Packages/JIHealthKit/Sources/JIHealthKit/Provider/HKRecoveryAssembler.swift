#if canImport(HealthKit)
import Foundation
import HealthKit
import JICore

/// Turns raw HealthKit samples into the hub's `[RecoveryDay]` shape, so every Recovery/Today tile
/// reads the same DTO whether the bytes came from the Mac hub (T1) or from the watch on this
/// device (T2).
///
/// `hrvRmssdMs` is the night's own native RMSSD (W-FIX3 C-h), dated to the wake-up day, from
/// readings inside that night's asleep segments only; `rhrBpm` is the day's minimum resting HR.
/// Both match the hub (WD-4: `app/vitals/apple_overnight.py`, `hae_bridge` RHR min), so a T2
/// device and the Mac hub show the same numbers for the same night.
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
        let rhrByDay = dailyMin(restingHeartRate, unit: HKUnit(from: "count/min"), window: window)
        let hrvByDay = dailyMean(hrv, unit: .secondUnit(with: .milli), window: window)
        let nights = HKSleepAssembler.nights(from: sleep, window: window)
        let rmssdByNight = nightlyRmssd(hrv, sleep: sleep, window: window)

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

    /// Asleep segments closer than this belong to one sleep period (hub `NIGHT_GAP`).
    static let nightGap: TimeInterval = 3 * 3600
    /// Asleep samples this close are one segment (the uploader's `sleepSegments` merge).
    static let segmentMergeGap: TimeInterval = 60

    private static let asleepValues: Set<Int> = [
        HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
    ]

    /// One sleep period: asleep segments with gaps ≤ `nightGap`.
    struct SleepPeriod {
        var segments: [(start: Date, end: Date)]
        var end: Date { segments.map(\.end).max() ?? .distantPast }
        var asleepSeconds: TimeInterval { segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
    }

    /// Port of the hub's `sleep_periods` + `main_nights` (B-65): asleep samples merged into
    /// segments (≤ 60 s apart), segments into periods (≤ 3 h apart); per wake day (local date of
    /// the period's end) the period with the most asleep time is that night's main sleep.
    static func mainNights(_ sleep: [HKSample], window: HKSampleWindow) -> [String: SleepPeriod] {
        var segments: [(start: Date, end: Date)] = []
        let asleep = sleep.compactMap { $0 as? HKCategorySample }
            .filter { asleepValues.contains($0.value) && $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
        for s in asleep {
            if let last = segments.last, s.startDate.timeIntervalSince(last.end) <= segmentMergeGap {
                segments[segments.count - 1].end = max(last.end, s.endDate)
            } else {
                segments.append((s.startDate, s.endDate))
            }
        }
        var periods: [SleepPeriod] = []
        for seg in segments {
            if let last = periods.last, seg.start.timeIntervalSince(last.end) <= nightGap {
                periods[periods.count - 1].segments.append(seg)
            } else {
                periods.append(SleepPeriod(segments: [seg]))
            }
        }
        var out: [String: SleepPeriod] = [:]
        for p in periods {
            guard let day = window.dayKey(for: p.end) else { continue }
            if let existing = out[day], existing.asleepSeconds >= p.asleepSeconds { continue }
            out[day] = p
        }
        return out
    }

    /// W-FIX3 C-h / WD-4: that night's own RMSSD (`RecoveryDay.hrvRmssdMs`, the hub's
    /// `hrv_rmssd_ms`). Only native RMSSD samples count — SDNN is a different statistic and never
    /// stands in (rule 5). A reading counts iff it lies inside an asleep segment of the wake day's
    /// main sleep period (hub `apple_overnight.classify`); no segments → no night value, never a
    /// guess. Mean rounded to 2 decimals like the hub.
    static func nightlyRmssd(_ samples: [HKSample], sleep: [HKSample], window: HKSampleWindow) -> [String: Double] {
        guard let rmssdType = HKReadKind.hrvRMSSDQuantityType else { return [:] }
        let unit = HKUnit.secondUnit(with: .milli)
        let nights = mainNights(sleep, window: window)
        guard !nights.isEmpty else { return [:] }
        var sums: [String: (total: Double, count: Int)] = [:]
        for case let sample as HKQuantitySample in samples where sample.quantityType == rmssdType {
            guard sample.quantity.is(compatibleWith: unit) else { continue }
            let ts = sample.startDate
            guard let day = nights.first(where: { $0.value.segments.contains { $0.start <= ts && ts <= $0.end } })?.key
            else { continue }
            let existing = sums[day] ?? (0, 0)
            sums[day] = (existing.total + sample.quantity.doubleValue(for: unit), existing.count + 1)
        }
        return sums.mapValues { (($0.total / Double($0.count)) * 100).rounded() / 100 }
    }

    /// The minimum of each day's quantity samples, bucketed by the local day of `startDate` —
    /// resting HR per day, the same rule as the hub (`hae_bridge` / Apple XML: the day's MIN).
    static func dailyMin(_ samples: [HKSample], unit: HKUnit, window: HKSampleWindow) -> [String: Double] {
        var out: [String: Double] = [:]
        for case let sample as HKQuantitySample in samples {
            guard let day = window.dayKey(for: sample.startDate), sample.quantity.is(compatibleWith: unit) else { continue }
            let value = sample.quantity.doubleValue(for: unit)
            out[day] = min(out[day] ?? value, value)
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

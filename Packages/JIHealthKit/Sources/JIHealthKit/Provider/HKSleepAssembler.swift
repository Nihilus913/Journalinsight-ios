#if canImport(HealthKit)
import Foundation
import HealthKit
import JICompute

/// One night of Apple sleep, bucketed and totalled — the input shape `JICompute.computeSleepScore`
/// (W6 parity port of `app/vitals/sleep_score.py`) takes.
///
/// `deepSec`/`remSec`/`awakeSec` are `nil` when the night carries **no stage breakdown at all**
/// (only `asleepUnspecified`/`inBed` samples — a pre-stage-tracking writer, or this app's own v1
/// backload marker). That distinction is load-bearing: `computeSleepScore` scores a missing stage
/// at 80% of its weight but a present-and-zero stage at 0%, so collapsing "no breakdown" into
/// `0` would make every unstaged night look far worse than it was.
public struct HKSleepNight: Sendable, Equatable {
    public let day: String
    public let durationSec: Int
    public let deepSec: Int?
    public let remSec: Int?
    public let awakeSec: Int?

    public init(day: String, durationSec: Int, deepSec: Int?, remSec: Int?, awakeSec: Int?) {
        self.day = day
        self.durationSec = durationSec
        self.deepSec = deepSec
        self.remSec = remSec
        self.awakeSec = awakeSec
    }

    /// The W6 parity score for this night. Delegates to `JICompute` — this package never does
    /// sleep-score arithmetic of its own (W7 card, L3 exit criterion).
    public var sleepScore: Int? {
        computeSleepScore(durationSec: durationSec, deepSec: deepSec, remSec: remSec, awakeSec: awakeSec)
    }
}

/// Groups HealthKit sleep-analysis category samples into nights.
public enum HKSleepAssembler {
    /// A night is attributed to the local calendar day of its sample's **end** time — the same
    /// convention the W2d upload path uses (`HKSampleMapping.sleepAnalysis`), so an Apple night
    /// lands on the morning you wake up, matching the hub's per-night `sleepEnd` reading.
    ///
    /// Samples whose end falls outside `window` are dropped. Durations are summed in whole
    /// seconds (rounded per sample) so the result is integral, as `computeSleepScore` expects.
    public static func nights(from samples: [HKSample], window: HKSampleWindow) -> [String: HKSleepNight] {
        struct Accumulator {
            var asleep = 0.0, deep = 0.0, rem = 0.0, awake = 0.0
            var hasStageDetail = false
        }
        var byDay: [String: Accumulator] = [:]
        for case let sample as HKCategorySample in samples {
            guard let day = window.dayKey(for: sample.endDate) else { continue }
            let seconds = sample.endDate.timeIntervalSince(sample.startDate)
            guard seconds > 0 else { continue }
            var acc = byDay[day] ?? Accumulator()
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                acc.deep += seconds; acc.asleep += seconds; acc.hasStageDetail = true
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                acc.rem += seconds; acc.asleep += seconds; acc.hasStageDetail = true
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                acc.asleep += seconds; acc.hasStageDetail = true
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                // Asleep, but the writer knew no stages — counts toward duration only.
                acc.asleep += seconds
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                acc.awake += seconds
            default:
                // `inBed` and any future case: not an asleep total, and not a stage.
                continue
            }
            byDay[day] = acc
        }
        var nights: [String: HKSleepNight] = [:]
        for (day, acc) in byDay {
            let duration = Int(acc.asleep.rounded())
            // A day with only `awake`/`inBed` samples has no sleep to score (mirrors
            // `computeSleepScore`'s own falsy-duration guard) — omit it rather than emit a zero.
            guard duration > 0 else { continue }
            nights[day] = HKSleepNight(
                day: day,
                durationSec: duration,
                deepSec: acc.hasStageDetail ? Int(acc.deep.rounded()) : nil,
                remSec: acc.hasStageDetail ? Int(acc.rem.rounded()) : nil,
                awakeSec: acc.hasStageDetail ? Int(acc.awake.rounded()) : nil
            )
        }
        return nights
    }
}
#endif

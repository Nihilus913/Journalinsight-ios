import Foundation
import JIHub

/// W9 L1 (B-30 P3, audit §4 item 8): turns the run's dense `heart_rate` series into per-workout
/// heart-rate samples that `HealthStoreWriting.add(_:to:)` associates with the `HKWorkout` — what
/// makes Fitness draw the HR chart, avg/max and zones for a third-party workout.
///
/// The HK-free half (`parse`/`select`/`syncId`) is what `BackloadMapper` uses to put the window's
/// readings on `BackloadWorkoutSampleSpec.hrSamples`; the HealthKit half (`samples(for:version:)`)
/// builds the objects. Sync id: `workout:<id>:hr:<HHMMSS>` (Zurich wall clock, same as every other
/// wire timestamp) — a copy of the standalone `hr:<ts>` sample, distinct so the workout's
/// force-overwrite path can delete + re-attach by id without touching the dense series.
public enum WorkoutHRAttacher {
    /// Wire entries -> parsed readings in time order; unparseable timestamps are dropped.
    public static func parse(_ entries: [BackloadHeartRateEntryDTO]) -> [BackloadWorkoutHRSample] {
        entries.compactMap { e in BackloadDateParsing.timestamp(e.ts).map { BackloadWorkoutHRSample(ts: $0, bpm: e.bpm) } }
            .sorted { $0.ts < $1.ts }
    }

    /// W11 (P4): the hub's per-second `workout_hr` entry -> parsed readings in time order (UTC `Z`
    /// timestamps; `BackloadDateParsing.timestamp` accepts them). Same drop rule as above.
    public static func parse(_ entry: BackloadWorkoutHrEntryDTO) -> [BackloadWorkoutHRSample] {
        entry.samples.compactMap { e in BackloadDateParsing.timestamp(e.ts).map { BackloadWorkoutHRSample(ts: $0, bpm: e.bpm) } }
            .sorted { $0.ts < $1.ts }
    }

    /// Readings with `start <= ts <= end`, in time order.
    public static func select(_ samples: [BackloadWorkoutHRSample], start: Date, end: Date) -> [BackloadWorkoutHRSample] {
        samples.filter { $0.ts >= start && $0.ts <= end }.sorted { $0.ts < $1.ts }
    }

    public static func syncId(workout syncId: String, at ts: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = BackloadDateParsing.zurich
        let c = cal.dateComponents([.hour, .minute, .second], from: ts)
        return String(format: "%@:hr:%02d%02d%02d", syncId, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

#if canImport(HealthKit)
import HealthKit

extension WorkoutHRAttacher {
    /// One `heartRate` `HKQuantitySample` per reading on `spec.hrSamples`, versioned like the
    /// workout (`version` = the workout's `HKMetadataKeySyncVersion`) so a hub correction to the
    /// activity re-versions its HR too.
    static func samples(for spec: BackloadWorkoutSampleSpec, version: Int) -> [HKQuantitySample] {
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit(from: "count/min")
        return spec.hrSamples.map { r in
            HKQuantitySample(
                type: type, quantity: HKQuantity(unit: unit, doubleValue: r.bpm), start: r.ts, end: r.ts,
                metadata: [HKMetadataKeySyncIdentifier: syncId(workout: spec.syncId, at: r.ts), HKMetadataKeySyncVersion: version])
        }
    }
}
#endif

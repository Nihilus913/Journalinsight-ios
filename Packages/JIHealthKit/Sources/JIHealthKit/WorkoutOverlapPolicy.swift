import Foundation

/// W9 L2 (B-30 P2.7, audit §4 item 7): skip a hub workout when another source (WHOOP, Strava,
/// Bevel, Apple Watch, Garmin Connect) already holds a workout overlapping MORE than half of the
/// hub workout's duration — that source stays authoritative for its era, and Fitness stops
/// listing the session twice. The largest single overlap decides; slivers from several sources
/// are not summed. Pure and HK-free: `HealthKitBackloader` feeds it the intervals it read through
/// `HealthStoreReading.workouts(start:end:)`.
public enum WorkoutOverlapPolicy {
    /// Fraction of the hub workout's duration another workout must cover before it is skipped.
    /// Strictly greater-than: an exact 50 % overlap is still written.
    public static let skipThreshold = 0.5

    public static func shouldSkip(start: Date, end: Date, existing: [DateInterval]) -> Bool {
        overlapFraction(start: start, end: end, existing: existing) > skipThreshold
    }

    /// Largest single overlap with `existing`, as a fraction of `[start, end]`'s duration; 0 for
    /// an empty or inverted hub window.
    public static func overlapFraction(start: Date, end: Date, existing: [DateInterval]) -> Double {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return 0 }
        let hub = DateInterval(start: start, end: end)
        let longest = existing.compactMap { hub.intersection(with: $0)?.duration }.max() ?? 0
        return longest / duration
    }
}

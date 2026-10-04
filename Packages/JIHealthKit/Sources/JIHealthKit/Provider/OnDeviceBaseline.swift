import Foundation
import JICore
#if canImport(HealthKit)
import HealthKit
#endif

/// W-ONDEVICE O-6 (B-20): where a stored night came from. Mirrors `JIPersistence.BaselineSource`
/// (raw values identical) — this package does not depend on the GRDB layer; the App adapts the
/// real `BaselineStore` to `NightlyBaselineStoring`.
public enum OnDeviceNightSource: String, Sendable, Hashable {
    /// Read from HealthKit on this phone (Garmin Connect copies filtered out, `HKSourceFilter`).
    case apple
    /// Only ever written by the one-time hub seed (O-8).
    case garmin
}

/// One source's nightly values for one wake-up day — raw, never aggregated (recompute-on-read).
public struct OnDeviceNight: Sendable, Equatable {
    public var source: OnDeviceNightSource
    public var date: String
    public var hrvRmssdMs: Double?
    public var rhrBpm: Double?
    public var sleepDurationSec: Double?
    public var sleepScore: Double?

    public init(source: OnDeviceNightSource, date: String, hrvRmssdMs: Double? = nil, rhrBpm: Double? = nil,
                sleepDurationSec: Double? = nil, sleepScore: Double? = nil) {
        self.source = source; self.date = date; self.hrvRmssdMs = hrvRmssdMs; self.rhrBpm = rhrBpm
        self.sleepDurationSec = sleepDurationSec; self.sleepScore = sleepScore
    }

    /// True when the night carries no value at all (never stored).
    public var isEmpty: Bool { hrvRmssdMs == nil && rhrBpm == nil && sleepDurationSec == nil && sleepScore == nil }

    /// The HealthKit-assembled recovery days as Apple nights (empty days dropped).
    public static func apple(from days: [RecoveryDay]) -> [OnDeviceNight] {
        days.map {
            OnDeviceNight(source: .apple, date: $0.date, hrvRmssdMs: $0.hrvRmssdMs, rhrBpm: $0.rhrBpm,
                          sleepDurationSec: $0.sleepDurationSec, sleepScore: $0.sleepScore)
        }.filter { !$0.isEmpty }
    }
}

/// The baseline store seam (`JIPersistence.BaselineStore` behind an App adapter; a fake in tests).
/// Contract: `record` is an upsert per `(source, date)` that also prunes past the 120-day window
/// ending on `today`; `nightly` returns every night on/before `through`, oldest first.
public protocol NightlyBaselineStoring: Sendable {
    func record(_ nights: [OnDeviceNight], today: String) throws
    func nightly(through: String) throws -> [OnDeviceNight]
}

/// W-ONDEVICE O-6: the HealthKit read path's source filter. `HKOwnWrites` already drops this app's
/// own Garmin backload; this drops the copies **Garmin Connect** writes into Health (audit 04-F1:
/// 105/115 "Apple" baseline nights were such copies), so an Apple baseline is built from Apple
/// readings only.
public enum HKSourceFilter {
    /// Bundle-id prefixes whose samples are never Apple readings.
    public static let excludedBundlePrefixes = ["com.garmin."]

    public static func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier?.lowercased() else { return false }
        return excludedBundlePrefixes.contains { id.hasPrefix($0) }
    }

    #if canImport(HealthKit)
    /// The real resolver: the sample's source bundle id (injectable — a package test cannot set a
    /// sample's source).
    public static let sampleBundle: @Sendable (HKSample) -> String? = { $0.sourceRevision.source.bundleIdentifier }

    public static func keep(_ samples: [HKSample], bundleOf: (HKSample) -> String?) -> [HKSample] {
        samples.filter { !isExcluded(bundleIdentifier: bundleOf($0)) }
    }
    #endif
}

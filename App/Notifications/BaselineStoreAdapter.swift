import Foundation
import JIHealthKit
import JIPersistence

/// W-ONDEVICE O-6: adapts the GRDB `BaselineStore` (JIPersistence) to the provider's
/// `NightlyBaselineStoring` seam (JIHealthKit). The two packages do not depend on each other, so
/// this is the only place that maps `OnDeviceNight` <-> `(source, metric, date, value)` rows.
struct BaselineStoreAdapter: NightlyBaselineStoring {
    let store: BaselineStore

    func record(_ nights: [OnDeviceNight], today: String) throws {
        try store.record(nights.flatMap(Self.rows), today: today)
    }

    func nightly(through: String) throws -> [OnDeviceNight] {
        try store.nightly(through: through).compactMap { night in
            guard let source = OnDeviceNightSource(rawValue: night.source.rawValue) else { return nil }
            return OnDeviceNight(
                source: source, date: night.date,
                hrvRmssdMs: night.values[.hrvRmssdMs], rhrBpm: night.values[.rhrBpm],
                sleepDurationSec: night.values[.sleepDurationSec], sleepScore: night.values[.sleepScore]
            )
        }
    }

    static func rows(_ night: OnDeviceNight) -> [BaselineSample] {
        guard let source = BaselineSource(rawValue: night.source.rawValue) else { return [] }
        let pairs: [(BaselineMetric, Double?)] = [
            (.hrvRmssdMs, night.hrvRmssdMs), (.rhrBpm, night.rhrBpm),
            (.sleepDurationSec, night.sleepDurationSec), (.sleepScore, night.sleepScore),
        ]
        return pairs.compactMap { metric, value in
            value.map { BaselineSample(source: source, metric: metric, date: night.date, value: $0) }
        }
    }
}

import Foundation
import JICore

/// W-ONDEVICE O-8 (Toby Q2, 2026-10-04): the optional one-time seed — the hub's last 120 nights
/// (`GET /vitals/recovery`) imported into the baseline store with `source = garmin`, so a phone
/// switched to the on-device verdict is not calibrating for another ~15 Apple nights.
///
/// `garmin` is deliberate even though the hub series is mixed Garmin + Apple: the compute's merge
/// (`merge_recovery_days`) puts this phone's own Apple night first and lets a seeded night fill
/// only where no Apple night exists (Garmin RMSSD x factor). Hub mode only — the App passes
/// `hub: nil` without a hub, and the seed is skipped.
public enum OnDeviceSeed {
    /// Nights asked of the hub — the store's retention window.
    public static let days = 120

    public enum Outcome: Sendable, Equatable {
        case seeded(Int)
        /// A `garmin` night is already stored: never re-import (idempotent).
        case alreadySeeded
        case noHub
    }

    /// - Parameter hub: `recovery(windowDays:)` of the hub provider, nil when not in Hub mode.
    public static func run(
        hub: (@Sendable (Int) async throws -> [RecoveryDay])?,
        store: any NightlyBaselineStoring,
        today: String
    ) async throws -> Outcome {
        guard let hub else { return .noHub }
        if try store.nightly(through: today).contains(where: { $0.source == .garmin }) { return .alreadySeeded }
        let days = try await hub(Self.days)
        // Only nights BEFORE today: tonight is this phone's own Apple night.
        let nights = OnDeviceNight.apple(from: days.filter { $0.date < today }).map {
            var n = $0
            n.source = .garmin
            return n
        }
        try store.record(nights, today: today)
        return .seeded(nights.count)
    }

    /// `YYYY-MM-DD` + `days` (fixed UTC Gregorian; a pure key shift).
    static func addDays(_ days: Int, to key: String) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let shifted = cal.date(byAdding: .day, value: days, to: date) else { return nil }
        return HKSampleWindow.isoDay(shifted, calendar: cal)
    }
}

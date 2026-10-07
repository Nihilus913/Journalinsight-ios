#if DEBUG
import Foundation
import HealthKit
import JIHealthKit
import os

/// W-OFFLINE2 OFF2-2: `-seed-healthkit-fixture` on a DEBUG launch writes `HealthKitFixtureSeed`'s
/// fixed data set (35 nights sleep/HRV/RHR, 14 days steps, 5 workouts) into this device's
/// HealthKit — the no-hub E2E on an erased simulator. ONE Health sheet asks share for the seeded
/// types AND read for every kind the on-device provider reads (merger: a second request in the same
/// process never shows its sheet on the iOS 27 sim); a second launch with the flag writes nothing. Skipped under `-no-healthkit`.
/// After the run it counts the `ji-fixture:` objects per type back out of HealthKit and logs them
/// (`log show --predicate 'category == "JIDebugSeed"'`). Never compiled into Release.
enum HealthKitFixtureSeeder {
    private static let log = Logger(subsystem: "toby913.JournalInsight", category: "JIDebugSeed")

    static func seedIfRequested(arguments: [String] = CommandLine.arguments) async {
        guard HealthKitFixtureSeed.isRequested(arguments), HealthKitLaunchGate.allowsHealthKit(arguments: arguments),
              HKHealthStore.isHealthDataAvailable() else { return }
        do {
            let types = HealthKitFixtureSeed.shareTypes
            // A freshly erased simulator's healthd can drop the first connection (Cocoa 4099):
            // retry the prompt a few times before giving up.
            for attempt in 1...4 {
                do {
                    try await HKHealthStore().requestAuthorization(toShare: types, read: Set(types.map { $0 as HKObjectType }))
                    break
                } catch where attempt < 4 {
                    log.notice("HealthKit fixture: auth attempt \(attempt, privacy: .public) failed, retrying")
                    try await Task.sleep(for: .seconds(3))
                }
            }
            let store = RealHealthStore()
            let report = try await HealthKitFixtureSeed.run(store: store)
            let since = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -(HealthKitFixtureSeed.nights + 2), to: Date()) ?? Date()
            var counts: [String] = []
            for type in types.sorted(by: { $0.identifier < $1.identifier }) {
                let ids = try await store.existingSyncVersions(sampleType: type, start: since, end: Date())
                counts.append("\(type.identifier)=\(ids.keys.filter { $0.hasPrefix(HealthKitFixtureSeed.syncPrefix) }.count)")
            }
            log.notice("HealthKit fixture: \(report.written, privacy: .public) written, \(report.skipped, privacy: .public) already present; in HK: \(counts.joined(separator: " "), privacy: .public)")
        } catch {
            log.error("HealthKit fixture seed failed: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif

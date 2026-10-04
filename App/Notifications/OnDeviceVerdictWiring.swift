import Foundation
import HealthKit
import JICore
import JIFeatures
import JIHealthKit
import JIPersistence
import UIKit
import UserNotifications

/// W-ONDEVICE O-9: the App half of the on-device verdict trigger. Everything testable lives in
/// `JIHealthKit` (`OnDeviceVerdictRunner`, `OnDevicePrewarm`, `HealthKitUploader.startBackgroundDelivery(onNight:)`);
/// this file only binds it to HealthKit, `UNUserNotificationCenter`, `BGTaskScheduler` and the
/// protected-data notification.
///
/// OFF unless BOTH hold: a DEBUG build with the Developer flag on (NO Release switch in this wave —
/// Release stays `.hub` until the 14-day dual run, O-10/B-44), and a compute engine is wired
/// (`engine`, the L1 JICompute adapter). With either missing nothing here runs and the hub stays
/// the only verdict.
@MainActor
enum OnDeviceVerdictWiring {
    nonisolated static let enabledKey = "ji.ondevice.verdict.enabled"

    /// The L1 compute (`HrvBand` + `mergeRecoveryDays` + `appleGateInputs` + `evaluate`) behind the
    /// `OnDeviceVerdictComputing` seam. Verifier: return the JICompute adapter once L1 is merged.
    nonisolated static var engine: (any OnDeviceVerdictComputing)? { nil }

    /// DEBUG + Developer flag + an engine. Release: always false.
    nonisolated static var isEnabled: Bool {
        #if DEBUG
        return engine != nil && UserDefaults.standard.bool(forKey: enabledKey)
        #else
        return false
        #endif
    }

    nonisolated static func baselineStore() -> (any NightlyBaselineStoring)? {
        guard let db = try? AppDatabase.onDisk() else { return nil }
        return BaselineStoreAdapter(store: BaselineStore(db: db))
    }

    /// The T2 provider with the on-device verdict wired when enabled (plain T2 otherwise).
    nonisolated static func makeProvider() -> HealthKitProvider {
        guard isEnabled, let engine, let baseline = baselineStore() else {
            return HealthKitProvider(store: RealHealthStoreReader())
        }
        return HealthKitProvider(store: RealHealthStoreReader(), baseline: baseline, onDevice: engine)
    }

    private static var runner: OnDeviceVerdictRunner?
    private static var provider: HealthKitProvider?
    private static var unlockObserver: (any NSObjectProtocol)?

    /// Builds the runner once (enabled builds only). `hub` = the current hub provider (shadow
    /// column + one-time seed); nil without a hub.
    static func install(hub: (any HealthDataProvider)?) {
        guard isEnabled, runner == nil else { return }
        let provider = makeProvider()
        self.provider = provider
        runner = OnDeviceVerdictRunner(
            compute: { day in try await provider.onDeviceVerdict(day: day) },
            notifier: LocalVerdictNotifier(),
            memory: UserDefaultsVerdictMemory()
        )
        unlockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in _ = await OnDeviceVerdictWiring.runner?.protectedDataBecameAvailable() }
        }
        if let hub, let baseline = baselineStore() {
            Task.detached(priority: .utility) {
                _ = try? await OnDeviceSeed.run(hub: { try await hub.recovery(windowDays: $0) }, store: baseline, today: provider.todayKey)
            }
        }
        schedulePrewarm()
    }

    /// The uploader's `onNight` hook: nil when disabled (the uploader then keeps `.hourly`).
    static var nightHook: (@Sendable () async -> Void)? {
        guard isEnabled else { return nil }
        return {
            guard let (runner, day) = await MainActor.run(body: { () -> (OnDeviceVerdictRunner, String)? in
                guard let r = OnDeviceVerdictWiring.runner, let p = OnDeviceVerdictWiring.provider else { return nil }
                return (r, p.todayKey)
            }) else { return }
            await runner.run(day: day)
        }
    }

    // MARK: - BGAppRefresh pre-warm (~04:45)

    /// Must run before launch finishes (BGTaskScheduler rule); a no-op when disabled.
    nonisolated static func registerPrewarm() {
        guard isEnabled else { return }
        BGTaskSchedulerAdapter().register(identifier: OnDevicePrewarm.taskIdentifier) {
            let warmed = await prewarm()
            await MainActor.run { schedulePrewarm() }
            return warmed
        }
    }

    static func schedulePrewarm() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let begin = OnDevicePrewarm.nextBegin(after: Date(), calendar: cal)
        try? BGTaskSchedulerAdapter().submitRefresh(identifier: OnDevicePrewarm.taskIdentifier, earliestBeginDate: begin)
    }

    /// Baselines (120 d of Apple nights into the store) + the last inputs, so the observer's
    /// compute after wake reads a warm store. Never posts anything.
    nonisolated static func prewarm() async -> Bool {
        guard let provider = await MainActor.run(body: { OnDeviceVerdictWiring.provider }) else { return false }
        return (try? await provider.refreshBaseline(windowDays: 120)) != nil
    }
}

/// The verdict as a local notification with the same `ji://gate` deep link as the 05:10 floor.
/// One request id per day, so a changed verdict replaces the earlier banner.
struct LocalVerdictNotifier: OnDeviceVerdictNotifying {
    func postVerdict(day: String, result: OnDeviceVerdictResult) async {
        let (linkKey, link) = await MainActor.run { (LocalVerdictFloor.deepLinkURLKey, LocalVerdictFloor.deepLinkURLString) }
        let content = UNMutableNotificationContent()
        let calibrating = OnDeviceVerdictLabel.isCalibrating(nights: result.baselineNights)
        content.title = calibrating ? OnDeviceVerdictLabel.calibrating(nights: result.baselineNights) : "Today's verdict"
        content.body = [result.verdict, result.reason].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        content.userInfo = [linkKey: link]
        let request = UNNotificationRequest(identifier: "ji.notifications.ondevice-verdict.\(day)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Last notified verdict per day, in `UserDefaults` (a background wake may be a fresh process).
/// Keeps only the last 7 days.
struct UserDefaultsVerdictMemory: OnDeviceVerdictMemory {
    private static let key = "ji.ondevice.verdict.lastNotified"
    // UserDefaults is thread-safe by documented contract (not annotated Sendable on this SDK).
    private nonisolated(unsafe) let defaults = UserDefaults.standard

    func lastNotified(day: String) -> String? {
        (defaults.dictionary(forKey: Self.key) as? [String: String])?[day]
    }

    func setLastNotified(_ verdict: String, day: String) {
        var map = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
        map[day] = verdict
        let keep = map.keys.sorted().suffix(7)
        defaults.set(map.filter { keep.contains($0.key) }, forKey: Self.key)
    }
}

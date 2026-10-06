import Foundation
import HealthKit
import JICore
import JIFeatures
import JIHealthKit
import JIHub
import JIPersistence
import UIKit
import UserNotifications

/// W-ONDEVICE O-9: the App half of the on-device verdict trigger. Everything testable lives in
/// `JIHealthKit` (`OnDeviceVerdictRunner`, `OnDevicePrewarm`, `HealthKitUploader.startBackgroundDelivery(onNight:)`);
/// this file only binds it to HealthKit, `UNUserNotificationCenter`, `BGTaskScheduler` and the
/// protected-data notification.
///
/// B-44 Option B (Toby 2026-10-04): ON in Release (every morning from 2026-10-05) whenever a
/// compute engine is wired (`engine`, the L1 JICompute adapter); DEBUG builds keep the Developer
/// flag. Baselines: Apple nights + the hub's Garmin nights (RG-04 seed). The gate and Decide read
/// the on-device verdict through `overlay` (`OnDeviceVerdictOverlay`); each morning's verdict is
/// uploaded to the hub (`OnDeviceVerdictUploadQueue`) and logged beside the hub's (O-10).
@MainActor
enum OnDeviceVerdictWiring {
    /// Same key as the Developer toggle (`JIFeatures.OnDeviceVerdictSection.enabledKey`).
    nonisolated static let enabledKey = "ji.ondevice.verdict.enabled"

    /// The L1 compute (`HrvBand` + `mergeRecoveryDays` + `appleGateInputs` + `evaluate`) behind the
    /// `OnDeviceVerdictComputing` seam (`JIComputeVerdictEngine`, JIHealthKit).
    nonisolated static var engine: (any OnDeviceVerdictComputing)? { JIComputeVerdictEngine(rules: gateRules) }

    /// RG-06 / B-112: the hub's rules (plan week) + the engine's own gate state, shared by every
    /// engine instance; refreshed from the hub before each compute (`prepareHubInputs`).
    nonisolated static let gateRules = OnDeviceGateRulesBox()

    /// Release: an engine is wired (B-44 Option B). DEBUG: + the Developer flag.
    /// BUG1-6 (RG-77): `-no-healthkit` also turns off the on-device compute path (its HealthKit
    /// reads, background delivery and prewarm), not only the uploader's cold-start request.
    nonisolated static var isEnabled: Bool {
        guard healthKitAllowed() else { return false }
        #if DEBUG
        return engine != nil && UserDefaults.standard.bool(forKey: enabledKey)
        #else
        return engine != nil
        #endif
    }

    nonisolated static func healthKitAllowed(arguments: [String] = CommandLine.arguments) -> Bool {
        HealthKitLaunchGate.allowsHealthKit(arguments: arguments)
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
    /// B-44: the current connection's hub (no overlay) — the upload target, re-pointed on reconnect.
    private static var currentHub: HubDataProvider?
    /// B-44: what `HubDataProvider` lays over its verdict (nil when disabled).
    private(set) static var overlay: (any MorningVerdictOverlay)?
    private static var unlockObserver: (any NSObjectProtocol)?

    /// Builds the runner + overlay once (enabled builds only). `hub` = the current hub provider
    /// WITHOUT the overlay (the shadow log's hub column + the upload target); nil without a hub.
    static func install(hub: HubDataProvider?) {
        currentHub = hub
        guard isEnabled, runner == nil else { return }
        let provider = makeProvider()
        self.provider = provider
        // O-10: each computed morning is logged next to the hub's verdict (dual run), and
        // B-44: uploaded to the hub (Outbox) so both sit side by side in the DB.
        let shadow = ShadowLogWriter.make(hub: hub)
        let upload = OnDeviceVerdictUploadQueue.make(hub: { await MainActor.run { OnDeviceVerdictWiring.currentHub } })
        let onResult: ShadowLogWriter.Write = { day, result, computedAt in
            await shadow?(day, result, computedAt)
            await upload?(day, result, computedAt)
        }
        let compute: OnDeviceVerdictOverlay.Compute = { day in try await OnDeviceVerdictWiring.compute(provider: provider, day: day) }
        runner = OnDeviceVerdictRunner(
            compute: compute,
            notifier: LocalVerdictNotifier(),
            memory: UserDefaultsVerdictMemory(),
            onResult: onResult,
            // W-FIX-P2 RG-17 (B-112): the hub's ntfy verdict banner wins — post the local one
            // only when the hub has no verdict for the day (it missed the morning).
            hubSent: { day in
                guard let hub = await MainActor.run(body: { OnDeviceVerdictWiring.currentHub }) else { return false }
                return (try? await hub.morningVerdict(date: day))?.date == day
            }
        )
        overlay = OnDeviceVerdictOverlay(startDay: overlayStartDay, today: { provider.todayKey },
                                         compute: compute, onResult: onResult)
        unlockObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in _ = await OnDeviceVerdictWiring.runner?.protectedDataBecameAvailable() }
        }
        // RG-04 (supersedes B-44 decision (3)): the hub's Garmin nights seed the baseline on the
        // first compute (`seedGarminNights`), so the phone reads the hub's 28 nights.
        schedulePrewarm()
    }

    nonisolated static var overlayStartDay: String {
        #if DEBUG
        if let d = UserDefaults.standard.string(forKey: OnDeviceVerdictOverlay.startOverrideKey), d.count == 10 { return d }
        #endif
        return OnDeviceVerdictOverlay.startDay
    }

    /// The on-device compute for `day`. DEBUG + `-ji.ondevice.fakeNights N`: from an in-memory store
    /// of N fake Apple nights (simulator, no HealthKit data) — same harness as `previewLine`.
    nonisolated static func compute(provider: HealthKitProvider, day: String) async throws -> OnDeviceVerdictResult? {
        #if DEBUG
        let fake = UserDefaults.standard.integer(forKey: fakeNightsKey)
        if fake > 0, let engine {
            let store = BaselineStoreAdapter(store: BaselineStore(db: try AppDatabase.inMemory()))
            try store.record(fakeNights(fake, day: day), today: day)
            let input = OnDeviceVerdictInput(day: day, nights: try store.nightly(through: day))
            guard var result = try engine.compute(input) else { return nil }
            result.inputsDigest = input.digest
            return result
        }
        #endif
        await seedGarminNights(day: day)
        await refreshPlanWeek()
        return try await provider.onDeviceVerdict(day: day)
    }

    /// RG-04 / B-120: before the first compute, the hub's Garmin nights complete the 28-night
    /// baseline exactly as the hub's own gate does (`OnDeviceSeed.runGarmin`, idempotent — a
    /// store that holds a Garmin night is never re-seeded). Without a hub: skipped (Apple only).
    /// RG-06: the plan week the hub's gate reads (`plan_from_rows` over `GET /planning/plan-sessions`),
    /// instead of the hard-coded weekday table. A failed read keeps the last week (or the table).
    nonisolated static func refreshPlanWeek() async {
        guard let hub = await MainActor.run(body: { OnDeviceVerdictWiring.currentHub }),
              let rows = try? await hub.planSessions() else { return }
        gateRules.setPlan(PlanScheduleResolver(planSessions: rows, fixedWeek: OnDeviceGateRulesBox.fixedWeek).week)
    }

    nonisolated static func seedGarminNights(day: String) async {
        guard let hub = await MainActor.run(body: { OnDeviceVerdictWiring.currentHub }),
              let store = baselineStore() else { return }
        _ = try? await OnDeviceSeed.runGarmin(hub: { n in try await hub.recoveryInputs(date: day, windowDays: n) },
                                              store: store, today: day)
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

    // MARK: - Developer screen estimate line

    /// DEBUG harness: `-ji.ondevice.fakeNights N` (launch argument) computes the Developer line
    /// from an in-memory baseline store holding N prior Apple nights + tonight instead of
    /// HealthKit (simulator screenshot of the calibrating label). 0 / absent = the real store.
    nonisolated static let fakeNightsKey = "ji.ondevice.fakeNights"

    /// Binds `OnDeviceVerdictPreview.load` (the Developer screen's estimate line). Enabled builds only.
    static func bindPreview() {
        guard isEnabled else { return }
        OnDeviceVerdictPreview.load = { await OnDeviceVerdictWiring.previewLine() }
    }

    nonisolated static func previewLine() async -> String {
        let provider = makeProvider()
        let day = provider.todayKey
        let fake = UserDefaults.standard.integer(forKey: fakeNightsKey)
        do {
            let result: OnDeviceVerdictResult?
            if fake > 0, let engine {
                let store = BaselineStoreAdapter(store: BaselineStore(db: try AppDatabase.inMemory()))
                try store.record(fakeNights(fake, day: day), today: day)
                result = try engine.compute(OnDeviceVerdictInput(day: day, nights: try store.nightly(through: day)))
            } else {
                result = try await provider.onDeviceVerdict(day: day)
            }
            guard let result else { return "No night yet for \(day)" }
            return OnDeviceVerdictLabel.headline(result)
        } catch {
            return "On-device verdict unavailable (\(error))"
        }
    }

    /// N prior Apple nights (RMSSD ~40 ms, 7.5 h) + tonight, for the DEBUG fake store.
    nonisolated static func fakeNights(_ n: Int, day: String) -> [OnDeviceNight] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let fmt = Date.ISO8601FormatStyle(timeZone: utc.timeZone).year().month().day()
        guard let base = try? fmt.parse(day) else { return [] }
        let prior = (1...max(1, n)).prefix(n).compactMap { i -> OnDeviceNight? in
            guard let date = utc.date(byAdding: .day, value: -i, to: base) else { return nil }
            let d = date.formatted(fmt)
            return OnDeviceNight(source: .apple, date: d, hrvRmssdMs: 38 + Double(i % 5), rhrBpm: 50,
                                 sleepDurationSec: 27_000, sleepScore: 80)
        }
        return prior.reversed() + [OnDeviceNight(source: .apple, date: day, hrvRmssdMs: 41, rhrBpm: 49,
                                                 sleepDurationSec: 27_360, sleepScore: 82)]
    }

    // MARK: - BGAppRefresh pre-warm (~04:45)

    /// Must run before launch finishes (BGTaskScheduler rule); a no-op when disabled.
    /// Called from `JournalInsightApp.init` AFTER `boot()` has run `install` — so `install`'s
    /// `schedulePrewarm()` is a no-op and the first submit happens here, once registered.
    static func registerPrewarm() {
        guard isEnabled, !prewarmRegistered else { return }
        BGTaskSchedulerAdapter().register(identifier: OnDevicePrewarm.taskIdentifier) {
            let warmed = await prewarm()
            await MainActor.run { schedulePrewarm() }
            return warmed
        }
        prewarmRegistered = true
        schedulePrewarm()
    }

    /// BGTaskScheduler raises an ObjC exception (launch crash) when a request is submitted for an
    /// identifier that is not registered yet.
    private static var prewarmRegistered = false

    static func schedulePrewarm() {
        guard prewarmRegistered else { return }
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

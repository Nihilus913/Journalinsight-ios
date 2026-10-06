import SwiftUI
import JIWorkouts
#if os(watchOS)
import WatchKit
import UserNotifications
#endif

/// W-B38-B B-4: wires the Watch strength logger — HealthKit engine → session controller,
/// WatchConnectivity transport → bridge, both into `StrengthLogViewModel`; registers the model
/// with `StrengthSessionLauncher` so the Action Button intent (B-6) reaches it.
@MainActor
final class StrengthLogComposition {
    let model: StrengthLogViewModel
    #if os(watchOS)
    private let engine: HealthKitStrengthWorkoutEngine
    private let transport: WatchConnectivityStrengthTransport
    private let notificationDelegate = WatchRestAlertDelegate()
    #endif

    init() {
        #if os(watchOS)
        let engine = HealthKitStrengthWorkoutEngine()
        let transport = WatchConnectivityStrengthTransport()
        let bridge = StrengthSessionWatchBridge(transport: transport)
        transport.onApplicationContext = { [weak bridge] in bridge?.receive(applicationContext: $0) }
        bridge.receive(applicationContext: transport.receivedApplicationContext)
        self.engine = engine
        self.transport = transport
        // B-43 P1: rest/timed-set end = haptic always (in-app tick) + a local notification that only
        // shows when the app is not frontmost (wrist down / another app) — `WatchRestAlertDelegate`
        // swallows it in the foreground, where the haptic already played (Toby 2026-10-04).
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        let model = StrengthLogViewModel(
            controller: StrengthWorkoutSessionController(engine: engine), bridge: bridge,
            haptic: { kind in
                WKInterfaceDevice.current().play(kind == .restDone ? .stop : .success)
            },
            restAlert: RestEndAlert(center: center))
        self.model = model
        // RG-76: a denied permission becomes the list's 'Notifications off' line.
        #if DEBUG
        // W-B78: the `WATCH_FAKE_SNAPSHOT=1` screenshot seam must not sit behind the system alert.
        let askPermission = WatchSnapshotStore.debugFakeSnapshotData(environment: ProcessInfo.processInfo.environment) == nil
        #else
        let askPermission = true
        #endif
        if askPermission {
            Task { await model.requestRestAlertPermission { await RestEndAlert.requestAuthorization(center) } }
        }
        #else
        model = StrengthLogViewModel(
            controller: StrengthWorkoutSessionController(engine: FakeStrengthWorkoutEngine()),
            bridge: StrengthSessionWatchBridge(transport: FakeStrengthBridgeTransport()))
        #endif
        StrengthSessionLauncher.shared.model = model
    }

    /// W-B78 (B-78): the HubSnapshot rides the SAME WCSession (one transport, one delegate) —
    /// live contexts go to `store.apply`, and a context delivered before launch is applied now.
    func connectSnapshots(_ store: WatchSnapshotStore) {
        #if os(watchOS)
        transport.onSnapshotContext = { [weak store] in store?.apply($0) }
        store.apply(context: transport.receivedApplicationContext)
        #endif
    }

    /// Sets go over the mirrored session while it runs; `transferUserInfo` otherwise (B-3).
    func sessionStateChanged() {
        #if os(watchOS)
        let live = model.controller.isActive && model.controller.isMirrored
        transport.workoutSession = live ? engine.workoutSession : nil
        #endif
    }
}

#if os(watchOS)
/// B-43 P1: frontmost → the rest-end alert is not presented (the in-app haptic covered it); any
/// other notification keeps the system's banner. A tap opens the app, whose root is the logger.
final class WatchRestAlertDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(RestEndAlert.isRestEnd(notification.request) ? [] : [.banner, .sound, .list])
    }
}
#endif

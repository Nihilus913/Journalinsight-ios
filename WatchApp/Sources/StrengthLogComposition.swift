import SwiftUI
import JIWorkouts
#if os(watchOS)
import WatchKit
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
        model = StrengthLogViewModel(
            controller: StrengthWorkoutSessionController(engine: engine), bridge: bridge,
            haptic: { kind in
                WKInterfaceDevice.current().play(kind == .restDone ? .stop : .success)
            })
        #else
        model = StrengthLogViewModel(
            controller: StrengthWorkoutSessionController(engine: FakeStrengthWorkoutEngine()),
            bridge: StrengthSessionWatchBridge(transport: FakeStrengthBridgeTransport()))
        #endif
        StrengthSessionLauncher.shared.model = model
    }

    /// Sets go over the mirrored session while it runs; `transferUserInfo` otherwise (B-3).
    func sessionStateChanged() {
        #if os(watchOS)
        let live = model.controller.isActive && model.controller.isMirrored
        transport.workoutSession = live ? engine.workoutSession : nil
        #endif
    }
}

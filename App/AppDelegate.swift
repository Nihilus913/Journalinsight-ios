import UIKit
import JIFeatures

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // B-18 p1: uncaught-NSException + MetricKit crash capture (local only, Version screen).
        CrashReporter.install()
        #if DEBUG
        installTouchOverlay()
        scheduleForcedCrashIfRequested()
        #endif
        return true
    }

    #if DEBUG
    /// B-18 p3: `-JIForceCrash YES` raises an NSException 2 s after launch so a simulator run can
    /// prove the capture end to end (crash → relaunch → About & version shows the record). DEBUG
    /// only — a Release build has no forced-crash path.
    private func scheduleForcedCrashIfRequested() {
        guard CommandLine.arguments.contains("-JIForceCrash") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NSException(name: .genericException, reason: "B-18 forced crash (-JIForceCrash)", userInfo: nil).raise()
        }
    }
    #endif

    #if DEBUG
    var window: UIWindow?   // SwiftUI creates its own; the touch overlay is a second, passthrough window (Task 4)
    private func installTouchOverlay() {
        // BUILD-3: `queue: .main` guarantees this closure runs on the main thread, but it is
        // still `nonisolated` to the Swift 6 checker. MainActor.assumeIsolated documents/asserts
        // that guarantee so the UIKit access below is statically main-actor-isolated with no warning.
        NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { note in
            // `note` (Notification) is non-Sendable; the region-isolation checker treats handing
            // it to the @MainActor closure below as a cross-isolation send. `nonisolated(unsafe)`
            // is safe here for the same reason `assumeIsolated` is: `queue: .main` already
            // guarantees this whole callback runs on the main thread.
            nonisolated(unsafe) let note = note
            MainActor.assumeIsolated {
                guard let scene = note.object as? UIWindowScene, scene.windows.first(where: { $0 is TouchIndicatorWindow }) == nil else { return }
                let overlay = TouchIndicatorWindow(windowScene: scene)
                overlay.windowLevel = .alert + 1
                overlay.backgroundColor = .clear
                overlay.isHidden = false
                overlay.rootViewController = UIViewController()
                overlay.rootViewController?.view.backgroundColor = .clear
                self.window = overlay
                // SwiftUI's own window owns every touch; mirror them to the overlay without interfering.
                let host = scene.keyWindow ?? scene.windows.first { !($0 is TouchIndicatorWindow) }
                host?.addGestureRecognizer(TouchObserverRecognizer(overlay: overlay))
            }
        }
    }
    #endif
}

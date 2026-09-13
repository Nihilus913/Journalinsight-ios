import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    #if DEBUG
    var window: UIWindow?   // SwiftUI creates its own; the touch overlay is a second, passthrough window (Task 4)
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { note in
            guard let scene = note.object as? UIWindowScene, scene.windows.first(where: { $0 is TouchIndicatorWindow }) == nil else { return }
            let overlay = TouchIndicatorWindow(windowScene: scene)
            overlay.windowLevel = .alert + 1
            overlay.backgroundColor = .clear
            overlay.isHidden = false
            overlay.rootViewController = UIViewController()
            overlay.rootViewController?.view.backgroundColor = .clear
            self.window = overlay
        }
        return true
    }
    #endif
}

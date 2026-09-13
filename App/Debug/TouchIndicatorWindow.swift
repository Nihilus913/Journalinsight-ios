#if DEBUG
import UIKit

/// Draws a ring at every touch so screen recordings carry a touch marker (iOS has no "Show taps").
final class TouchIndicatorWindow: UIWindow {
    private var rings: [UITouch: UIView] = [:]

    /// Fed by `TouchObserverRecognizer` on SwiftUI's key window. A window whose `hitTest` returns
    /// nil never owns a touch, so `sendEvent` would never fire here; iOS 27 SwiftUI also ignores
    /// `NSPrincipalClass` (`UIApplication.shared` is `SwiftUIApplication`), so a `UIApplication`
    /// subclass is not an option either (Task 16 review).
    func observe(_ touches: Set<UITouch>) {
        for touch in touches {
            switch touch.phase {
            case .began: add(touch)
            case .moved: rings[touch]?.center = touch.location(in: self)
            case .ended, .cancelled: remove(touch)
            default: break
            }
        }
    }

    private func add(_ touch: UITouch) {
        let ring = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        ring.center = touch.location(in: self)
        ring.layer.cornerRadius = 22
        ring.layer.borderWidth = 3
        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.6).cgColor
        ring.isUserInteractionEnabled = false
        addSubview(ring)
        rings[touch] = ring
    }

    private func remove(_ touch: UITouch) {
        rings[touch]?.removeFromSuperview()
        rings[touch] = nil
    }

    // Passthrough: returning nil means this window is never the hit-test target, so touches
    // reach the app's own windows underneath; the recognizer below feeds `observe(_:)` instead.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Never recognizes, never cancels: it only mirrors the key window's touches to the overlay.
final class TouchObserverRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var overlay: TouchIndicatorWindow?

    init(overlay: TouchIndicatorWindow) {
        self.overlay = overlay
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { overlay?.observe(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { overlay?.observe(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { overlay?.observe(touches); state = .failed }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { overlay?.observe(touches); state = .failed }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif

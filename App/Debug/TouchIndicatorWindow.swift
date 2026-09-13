#if DEBUG
import UIKit

/// Draws a ring at every touch so screen recordings carry a touch marker (iOS has no "Show taps").
final class TouchIndicatorWindow: UIWindow {
    private var rings: [UITouch: UIView] = [:]

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
        guard event.type == .touches, let touches = event.allTouches else { return }
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
    // reach the app's own windows underneath, while `sendEvent` above still observes them.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
#endif

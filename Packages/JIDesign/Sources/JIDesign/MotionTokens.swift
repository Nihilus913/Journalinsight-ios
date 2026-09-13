import SwiftUI

/// From mobile/src/theme/tokens.ts MOTION — perceptual durations; SwiftUI's spring(duration:) is perceptual too.
public enum JIMotion {
    public static let press = Animation.spring(duration: 0.10, bounce: 0)
    public static let standard = Animation.spring(duration: 0.50, bounce: 0)
    public static let overshoot = Animation.spring(duration: 0.50, bounce: 0.4) // bounce 0.4 ≙ RN dampingRatio 0.6 (dampingRatio = 1 − bounce)
    public static let reveal = Animation.spring(duration: 2.8, bounce: 0)
    public static let micro: Duration = .milliseconds(200)
    public static let card: Duration = .milliseconds(400)
    public static let staggerXs: Duration = .milliseconds(70)
}

import Foundation
import Observation
import UserNotifications
import JIWorkouts

/// B-43 P1 — the seam a rest-end notification tap (`ji://strength-log`, App `DeepLink.strengthLog`)
/// goes through to reach the logger: the App focuses the Training tab and calls `request()`;
/// `TrainingView` consumes it (on appear too, so a cold-start tap that lands before the tab is
/// mounted still opens the logger) and re-shows the logger it already holds — its countdown intact —
/// or opens a fresh one that resumes today's open session from the store.
@Observable @MainActor
public final class StrengthLoggerOpenRequest {
    public static let shared = StrengthLoggerOpenRequest()
    public private(set) var pending = false
    public init() {}
    public func request() { pending = true }
    /// True once per request.
    public func consume() -> Bool {
        guard pending else { return false }
        pending = false
        return true
    }
}

extension RestEndAlert {
    /// The app's one alert on the real centre (one instance, so its planned end is the truth for
    /// every logger the app opens). Touched only by the app's logger (host tests never reach it).
    @MainActor public static let live = RestEndAlert(center: UNUserNotificationCenter.current())
}

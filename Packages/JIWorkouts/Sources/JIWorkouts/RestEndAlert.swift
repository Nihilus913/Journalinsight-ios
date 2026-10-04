import Foundation
import JICompute
import UserNotifications

// B-43 P1 — the rest / timed-set end alert. While the logger is frontmost the in-view countdown
// and the in-process haptic (`StrengthLogHaptic`) cover the end; when the phone is locked, the app
// is backgrounded or the Watch is wrist-down nothing runs, so every countdown change re-plans ONE
// pending time-interval `UNNotification` at the countdown's end: started → added, +15/+30 s →
// replaced at the new end, skip / finish / complete → removed. Shared by the Watch model
// (`JIWorkouts.StrengthLogViewModel`) and the phone logger (`JIFeatures.StrengthLogViewModel`).
// A tap opens the logger: `userInfo["url"]` = `ji://strength-log` (the phone's `DeepLink`); on the
// Watch the tap opens the app, whose root is the logger.

/// The slice of `UNUserNotificationCenter` the alert uses — `UNUserNotificationCenter` already has
/// both methods (the conformance below is empty); a fake in tests.
public protocol RestAlertNotificationCenter: AnyObject, Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: RestAlertNotificationCenter {}

@MainActor
public final class RestEndAlert {
    public nonisolated static let identifier = "ji.workout.rest-end"
    public nonisolated static let kindKey = "kind"
    public nonisolated static let kindTag = "rest-end"
    /// Same key as `ReminderScheduler.deepLinkURLKey` / `LocalVerdictFloor.deepLinkURLKey`.
    public nonisolated static let deepLinkURLKey = "url"
    public nonisolated static let loggerURL = "ji://strength-log"

    private let center: any RestAlertNotificationCenter
    /// The end currently planned (nil = none) — an unchanged countdown re-plans nothing.
    public private(set) var plannedEnd: Date?
    /// Every remove/add runs on this chain in call order, so a skip right after a start can never
    /// be overtaken by the start's (async) add.
    private var chain: Task<Void, Never>?

    public init(center: any RestAlertNotificationCenter) { self.center = center }

    /// Re-plans the alert for `timer` (call on every countdown change). `exercise` names the next
    /// set in the body when known.
    public func sync(_ timer: SetTimer, exercise: String? = nil, now: Date) {
        let end: Date? = {
            guard timer.phase != .idle, let e = timer.endsAt, e > now else { return nil }
            return e
        }()
        guard end != plannedEnd else { return }
        plannedEnd = end
        let request = end.map { Self.request(phase: timer.phase, endsAt: $0, exercise: exercise, now: now) }
        let center = self.center
        let previous = chain
        chain = Task {
            await previous?.value
            center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            if let request { try? await center.add(request) }
        }
    }

    /// Drops any pending alert (session ended / logger torn down).
    public func cancel() { sync(SetTimer(), now: .distantPast) }

    /// Waits until every queued remove/add has reached the centre (tests).
    public func flush() async { await chain?.value }

    /// Asks once for alert permission (no-op when already decided); false on denial or failure.
    public static func requestAuthorization(_ center: UNUserNotificationCenter = .current()) async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    // MARK: pure

    public nonisolated static func title(phase: SetTimer.Phase) -> String {
        phase == .timedSet ? "Time's up ⏱️" : "Rest over 💪"
    }

    public nonisolated static func body(phase: SetTimer.Phase, exercise: String?) -> String {
        let name = exercise?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (phase, name?.isEmpty == false ? name : nil) {
        case (.timedSet, let n?): return "\(n): hold done — tap to log it."
        case (.timedSet, nil): return "Hold done — tap to log it."
        case (_, let n?): return "Next set of \(n) — tap to open the logger."
        case (_, nil): return "Next set — tap to open the logger."
        }
    }

    public nonisolated static func request(phase: SetTimer.Phase, endsAt: Date, exercise: String?, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title(phase: phase)
        content.body = body(phase: phase, exercise: exercise)
        content.sound = .default
        content.threadIdentifier = identifier
        content.userInfo = [kindKey: kindTag, deepLinkURLKey: loggerURL]
        // A time-interval trigger needs > 0 s; a countdown inside its last second still alerts.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, endsAt.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    /// True for a notification this alert planned (the Watch foreground filter reads it).
    public nonisolated static func isRestEnd(_ request: UNNotificationRequest) -> Bool {
        request.identifier == identifier
    }
}

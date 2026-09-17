import Foundation
import UserNotifications

/// W2c-L4 — the 05:10 local "floor" reminder (PARITY P-notifications), mirroring the RN oracle's
/// `GATE_FLOOR_REMINDER_*` family (`HealthTraining/mobile/src/notify/reminders.ts`, E10-9): a daily
/// local notification that fires even when the hub hasn't pushed anything, nudging the user to open
/// today's readiness verdict. Its payload carries a `ji://gate` deep link (consumed by
/// `NtfyDeepLinkHandler`) rather than relying on a cold app-icon tap, so a tap lands straight on the
/// gate instead of wherever the app last was.
///
/// Split from scheduling (an effectful `UNUserNotificationCenter` call, hard to unit test) into pure
/// content/trigger/request builders below, so the exit criterion ("notification request built for
/// 05:10") is a plain value test with no notification-center mock needed.
enum LocalVerdictFloor {
    static let identifier = "ji.notifications.verdict-floor"
    static let deepLinkURLKey = "url"
    static let deepLinkURLString = "ji://gate"
    static let defaultHour = 5
    static let defaultMinute = 10

    static let title = "Readiness floor"
    static let body = "05:10 local — check today's readiness verdict."

    /// Pure: the notification's content, including the `data.url` deep-link payload
    /// `NtfyDeepLinkHandler` reads back out on tap. `userInfo` values must be property-list types
    /// (UNUserNotificationCenter requirement), so the URL travels as a plain `String`.
    static func content() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [deepLinkURLKey: deepLinkURLString]
        return content
    }

    /// Pure: a daily calendar trigger firing at `hour:minute` local time (device calendar/timezone
    /// — deliberately NOT `JICompute`'s fixed-zone rule; this is UI-layer wall-clock scheduling, not
    /// a compute-parity calculation). `repeats: true` re-fires every day without a re-schedule call.
    static func trigger(hour: Int = defaultHour, minute: Int = defaultMinute) -> UNCalendarNotificationTrigger {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    }

    /// Pure: the full request `schedule(hour:minute:)` hands to the notification center. Exposed
    /// separately so tests can assert on the built value (identifier, content, trigger fire time)
    /// without touching `UNUserNotificationCenter` at all.
    static func request(hour: Int = defaultHour, minute: Int = defaultMinute) -> UNNotificationRequest {
        UNNotificationRequest(identifier: identifier, content: content(), trigger: trigger(hour: hour, minute: minute))
    }

    /// Cancels any previously-scheduled floor reminder, then adds a fresh one for `hour:minute` —
    /// same "cancel-then-add" shape as the RN oracle's `scheduleDailyGateFloorReminder` (idempotent:
    /// calling it again with the same identifier just replaces the pending request, but going
    /// through `remove` first keeps behavior explicit if the identifier scheme ever changes).
    /// Authorization is NOT requested here — callers (`JournalInsightApp`) request it once at
    /// startup; scheduling with unauthorized permissions is a harmless no-op fire, per
    /// `UNUserNotificationCenter` semantics.
    static func schedule(
        hour: Int = defaultHour,
        minute: Int = defaultMinute,
        center: UNUserNotificationCenter = .current()
    ) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(request(hour: hour, minute: minute))
    }

    static func cancel(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

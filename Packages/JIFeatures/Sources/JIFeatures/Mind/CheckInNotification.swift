import Foundation
import UserNotifications
import JICore

// W-B102 C-2 (BP-23a mockup frame 01): the data-triggered check-in is ONE dated, non-repeating
// local notification through the existing `ReminderNotificationCenter` seam (works hub-less). Its
// tap lands on `ji://checkin?trigger=<rule>` via the same `url` userInfo key the 05:10 floor uses.

public nonisolated enum CheckInNotification {
    public static let identifier = "ji.reminders.data-checkin"
    public static let tag = "data-checkin"
    /// Nothing fires at or after this hour (quiet 22:00–07:00) …
    public static let quietStartHour = 22
    /// … nor before the earliest time (after the 05:10 readiness floor).
    public static let earliest = ReminderTime(hour: 9, minute: 0)

    public static func deepLink(_ rule: CheckInRule) -> String { "ji://checkin?trigger=\(rule.rawValue)" }

    /// Device-local wall clock (hour/minute of "now") → when today's prompt fires, nil = too late
    /// today (inside quiet hours). Never before `earliest`, otherwise one minute from now.
    public static func fireTime(now: DateComponents) -> ReminderTime? {
        let minutes = (now.hour ?? 0) * 60 + (now.minute ?? 0) + 1
        let fire = max(minutes, earliest.hour * 60 + earliest.minute)
        guard fire < quietStartHour * 60 else { return nil }
        return ReminderTime(hour: fire / 60, minute: fire % 60)
    }

    public static func request(prompt: CheckInPrompt, at time: ReminderTime) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = prompt.title
        content.body = prompt.body
        content.sound = .default
        content.userInfo = [ReminderScheduler.kindKey: tag, ReminderScheduler.deepLinkURLKey: deepLink(prompt.rule)]
        let parts = prompt.day.iso.split(separator: "-").compactMap { Int($0) }
        var c = DateComponents()
        if parts.count == 3 { c.year = parts[0]; c.month = parts[1]; c.day = parts[2] }
        c.hour = time.hour; c.minute = time.minute
        return UNNotificationRequest(identifier: identifier, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false))
    }
}

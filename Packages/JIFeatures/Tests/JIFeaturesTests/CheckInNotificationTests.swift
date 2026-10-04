import Foundation
import Testing
import UserNotifications
import JICore
@testable import JIFeatures

// W-B102 C-2 — the one-shot data-triggered notification (quiet 22:00–07:00, earliest 09:00).

private func at(_ h: Int, _ m: Int) -> DateComponents { DateComponents(hour: h, minute: m) }

struct CheckInNotificationTests {
    @Test func beforeEarliestFiresAtNine() {
        #expect(CheckInNotification.fireTime(now: at(6, 30)) == ReminderTime(hour: 9, minute: 0))
        #expect(CheckInNotification.fireTime(now: at(5, 10)) == ReminderTime(hour: 9, minute: 0))
    }

    @Test func daytimeFiresAMinuteLater() {
        #expect(CheckInNotification.fireTime(now: at(9, 12)) == ReminderTime(hour: 9, minute: 13))
        #expect(CheckInNotification.fireTime(now: at(21, 58)) == ReminderTime(hour: 21, minute: 59))
    }

    @Test func quietHoursNeverFire() {
        #expect(CheckInNotification.fireTime(now: at(21, 59)) == nil)   // 22:00 is already quiet
        #expect(CheckInNotification.fireTime(now: at(22, 5)) == nil)
        #expect(CheckInNotification.fireTime(now: at(23, 59)) == nil)
    }

    @Test func requestCarriesDeepLinkAndOneShotTrigger() throws {
        let p = CheckInPrompt(rule: .amber2, day: DayKey(iso: "2026-10-04")!, title: "Two amber mornings in a row",
                              body: "Oct 3 Modified, Oct 4 Rest. How do you feel? 10 seconds.", why: "w", morningsLine: nil)
        let r = CheckInNotification.request(prompt: p, at: ReminderTime(hour: 9, minute: 13))
        #expect(r.identifier == "ji.reminders.data-checkin")
        #expect(r.content.title == p.title)
        #expect(r.content.body == p.body)
        #expect(r.content.userInfo[ReminderScheduler.deepLinkURLKey] as? String == "ji://checkin?trigger=amber2")
        #expect(r.content.userInfo[ReminderScheduler.kindKey] as? String == "data-checkin")
        let t = try #require(r.trigger as? UNCalendarNotificationTrigger)
        #expect(!t.repeats)
        #expect(t.dateComponents.year == 2026 && t.dateComponents.month == 10 && t.dateComponents.day == 4)
        #expect(t.dateComponents.hour == 9 && t.dateComponents.minute == 13)
    }
}

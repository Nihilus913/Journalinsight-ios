//
//  NotificationManager.swift
//  JournalInsight
//
//  Created by Claude on 24.03.2026.
//

import Foundation
import UserNotifications

enum NotificationManager {
    private static let journalReminderID = "daily-journal-reminder"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func scheduleDailyReminder(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [journalReminderID])

        let content = UNMutableNotificationContent()
        content.title = "Time to Journal"
        content.body = "Take a moment to reflect on your day."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: journalReminderID, content: content, trigger: trigger)

        center.add(request)
    }

    static func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [journalReminderID])
    }

    // Workout reminder — fires only on scheduled training days
    static let workoutReminderIDPrefix = "workoutReminder_"

    static func scheduleWorkoutReminder(weekdays: [Int], hour: Int, minute: Int, planSummary: String) {
        let center = UNUserNotificationCenter.current()
        // Remove all existing workout reminders before rescheduling
        center.removePendingNotificationRequests(withIdentifiers:
            (1...7).map { "\(workoutReminderIDPrefix)\($0)" })

        let content = UNMutableNotificationContent()
        content.sound = .default

        for weekday in weekdays {
            content.title = weekdayName(weekday) + " plan is ready"
            content.body = planSummary.isEmpty
                ? "Your training session is scheduled for today."
                : planSummary

            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let id = "\(workoutReminderIDPrefix)\(weekday)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request)
        }
    }

    static func cancelWorkoutReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: (1...7).map { "\(workoutReminderIDPrefix)\($0)" })
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names.indices.contains(weekday) ? names[weekday] : "Today"
    }
}

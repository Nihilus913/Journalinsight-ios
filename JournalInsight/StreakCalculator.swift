//
//  StreakCalculator.swift
//  JournalInsight
//
//  Created by Claude on 24.03.2026.
//

import Foundation

enum StreakCalculator {
    /// Computes the current consecutive-day streak ending today.
    static func currentStreak(from entries: [JournalEntry]) -> Int {
        let calendar = Calendar.current
        let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.date) }).sorted(by: >)
        var streak = 0
        var expected = calendar.startOfDay(for: Date())

        for date in uniqueDays {
            if date == expected {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: expected) else { break }
                expected = prev
            } else if date < expected {
                break
            }
        }
        return streak
    }

    /// Computes the longest consecutive-day streak in the entry history.
    static func bestStreak(from entries: [JournalEntry]) -> Int {
        let calendar = Calendar.current
        let uniqueDays = Set(entries.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !uniqueDays.isEmpty else { return 0 }

        var best = 1
        var current = 1

        for i in 1..<uniqueDays.count {
            let prev = uniqueDays[i - 1]
            let next = uniqueDays[i]
            if calendar.date(byAdding: .day, value: 1, to: prev) == next {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    /// Returns a human-readable label for the average time-of-day of entries.
    static func preferredTimeOfDay(from entries: [JournalEntry]) -> String {
        guard !entries.isEmpty else { return "—" }
        let calendar = Calendar.current
        let hours = entries.map { calendar.component(.hour, from: $0.date) }
        let averageHour = Double(hours.reduce(0, +)) / Double(hours.count)
        switch averageHour {
        case ..<7: return "Early Morning"
        case 7..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }
}

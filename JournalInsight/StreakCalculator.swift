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
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(nextDay, inSameDayAs: next) {
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
        let radians: [Double] = entries.map {
            let hour = Double(calendar.component(.hour, from: $0.date))
            return hour * .pi / 12.0                                     // 0…2π
        }
        let sumSin = radians.reduce(0.0) { $0 + sin($1) }
        let sumCos = radians.reduce(0.0) { $0 + cos($1) }
        let n = Double(radians.count)
        let meanRad = atan2(sumSin / n, sumCos / n)
        let rawHour = meanRad * 12.0 / .pi
        let meanHour = (rawHour + 24.0).truncatingRemainder(dividingBy: 24.0)
        // "Night" wraps midnight (21–24 ∪ 0–5). Early Morning is 5–7.
        // This matches how a circular mean of {23, 0, 1} (centered at midnight)
        // is intuitively "Night" rather than "Early Morning".
        switch meanHour {
        case ..<5:    return "Night"
        case 5..<7:   return "Early Morning"
        case 7..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default:      return "Night"
        }
    }
}

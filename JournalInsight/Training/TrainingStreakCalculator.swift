import Foundation

enum TrainingStreakCalculator {

    static func currentStreak(from entries: [WorkoutEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        guard days.contains(today) else { return 0 }
        var streak = 0
        var check = today
        while days.contains(check) {
            streak += 1
            check = cal.date(byAdding: .day, value: -1, to: check)!
        }
        return streak
    }

    static func bestStreak(from entries: [WorkoutEntry]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let cal = Calendar.current
        let days = Set(entries.map { cal.startOfDay(for: $0.date) }).sorted()
        var best = 1, current = 1
        for i in 1 ..< days.count {
            let diff = cal.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 0
            current = diff == 1 ? current + 1 : 1
            best = max(best, current)
        }
        return best
    }

    static let milestones: [Int] = [1, 3, 7, 14, 30, 60, 90]

    static func milestoneLabel(for days: Int) -> String {
        switch days {
        case 1:  return "First session back"
        case 3:  return "Three in a row"
        case 7:  return "One week consistent"
        case 14: return "Two weeks"
        case 30: return "One month"
        case 60: return "Two months"
        case 90: return "Three months"
        default: return "\(days) days"
        }
    }
}

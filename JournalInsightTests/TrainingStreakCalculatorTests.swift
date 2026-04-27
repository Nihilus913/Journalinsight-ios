import Testing
import Foundation
@testable import JournalInsight

@Suite("TrainingStreakCalculatorTests")
struct TrainingStreakCalculatorTests {

    private func makeEntry(daysAgo: Int, source: WorkoutSource = .manual) -> WorkoutEntry {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return WorkoutEntry(date: date, source: source, durationSec: 3600)
    }

    @Test("Returns 0 for empty entries")
    func emptyEntries() {
        #expect(TrainingStreakCalculator.currentStreak(from: []) == 0)
    }

    @Test("Returns 0 when no entry today")
    func noEntryToday() {
        let entries = [makeEntry(daysAgo: 1), makeEntry(daysAgo: 2)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 0)
    }

    @Test("Returns 1 when only today has entry")
    func onlyToday() {
        let entries = [makeEntry(daysAgo: 0)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 1)
    }

    @Test("Counts consecutive days including today")
    func consecutiveDays() {
        let entries = [makeEntry(daysAgo: 0), makeEntry(daysAgo: 1), makeEntry(daysAgo: 2)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 3)
    }

    @Test("Stops streak at gap")
    func breakInStreak() {
        let entries = [makeEntry(daysAgo: 0), makeEntry(daysAgo: 1),
                       makeEntry(daysAgo: 3), makeEntry(daysAgo: 4)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 2)
    }

    @Test("Multiple workouts same day count as one")
    func sameDay() {
        let entries = [makeEntry(daysAgo: 0), makeEntry(daysAgo: 0), makeEntry(daysAgo: 1)]
        #expect(TrainingStreakCalculator.currentStreak(from: entries) == 2)
    }

    @Test("bestStreak returns 0 for empty")
    func bestStreakEmpty() {
        #expect(TrainingStreakCalculator.bestStreak(from: []) == 0)
    }

    @Test("bestStreak finds longest run")
    func bestStreakLongest() {
        let entries = [makeEntry(daysAgo: 10), makeEntry(daysAgo: 11), makeEntry(daysAgo: 12),
                       makeEntry(daysAgo: 15), makeEntry(daysAgo: 16)]
        #expect(TrainingStreakCalculator.bestStreak(from: entries) == 3)
    }
}

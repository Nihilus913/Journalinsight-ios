//
//  JournalInsightTests.swift
//  JournalInsightTests
//
//  Created by Tobias Tensfeldt on 25.04.2025.
//

import Testing
import Foundation
@testable import JournalInsight

// MARK: - Streak Calculator Tests

@Suite("Streak Calculator")
struct StreakCalculatorTests {
    private let calendar = Calendar.current

    private func entry(daysAgo: Int, hour: Int = 12) -> JournalEntry {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        let withHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
        return JournalEntry(date: withHour, text: "Test entry", duration: 600)
    }

    @Test("Current streak with consecutive days ending today")
    func currentStreakConsecutive() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 1), entry(daysAgo: 2)]
        #expect(StreakCalculator.currentStreak(from: entries) == 3)
    }

    @Test("Current streak is 0 when no entry today")
    func currentStreakNoEntryToday() {
        let entries = [entry(daysAgo: 1), entry(daysAgo: 2)]
        #expect(StreakCalculator.currentStreak(from: entries) == 0)
    }

    @Test("Current streak with a gap")
    func currentStreakWithGap() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 1), entry(daysAgo: 3)]
        #expect(StreakCalculator.currentStreak(from: entries) == 2)
    }

    @Test("Current streak with no entries")
    func currentStreakEmpty() {
        #expect(StreakCalculator.currentStreak(from: []) == 0)
    }

    @Test("Current streak counts multiple entries per day as one")
    func currentStreakDuplicateDays() {
        let entries = [entry(daysAgo: 0), entry(daysAgo: 0), entry(daysAgo: 1)]
        #expect(StreakCalculator.currentStreak(from: entries) == 2)
    }

    @Test("Best streak finds longest consecutive run")
    func bestStreakFindsLongest() {
        let entries = [
            entry(daysAgo: 0), entry(daysAgo: 1),
            entry(daysAgo: 5), entry(daysAgo: 6), entry(daysAgo: 7), entry(daysAgo: 8)
        ]
        #expect(StreakCalculator.bestStreak(from: entries) == 4)
    }

    @Test("Best streak with no entries returns 0")
    func bestStreakEmpty() {
        #expect(StreakCalculator.bestStreak(from: []) == 0)
    }

    @Test("Best streak with single entry returns 1")
    func bestStreakSingleEntry() {
        #expect(StreakCalculator.bestStreak(from: [entry(daysAgo: 3)]) == 1)
    }

    @Test("Preferred time of day returns Morning for morning entries")
    func preferredTimeMorning() {
        let entries = [entry(daysAgo: 0, hour: 9), entry(daysAgo: 1, hour: 10)]
        #expect(StreakCalculator.preferredTimeOfDay(from: entries) == "Morning")
    }

    @Test("Preferred time of day returns Evening for evening entries")
    func preferredTimeEvening() {
        let entries = [entry(daysAgo: 0, hour: 19), entry(daysAgo: 1, hour: 20)]
        #expect(StreakCalculator.preferredTimeOfDay(from: entries) == "Evening")
    }

    @Test("Preferred time of day returns dash for empty entries")
    func preferredTimeEmpty() {
        #expect(StreakCalculator.preferredTimeOfDay(from: []) == "—")
    }
}

// MARK: - JournalEntry Tests

@Suite("Journal Entry")
struct JournalEntryTests {

    @Test("JournalEntry initializes with correct values")
    func initializesCorrectly() {
        let date = Date()
        let entry = JournalEntry(date: date, text: "Hello", duration: 300)
        #expect(entry.date == date)
        #expect(entry.text == "Hello")
        #expect(entry.duration == 300)
    }
}

// MARK: - Goal Tests

@Suite("Goal")
struct GoalTests {

    @Test("Goal clamps progress to 0...1")
    func progressClamping() {
        let overGoal = Goal(title: "Test", targetDate: Date(), progress: 1.5)
        #expect(overGoal.progress == 1.0)

        let underGoal = Goal(title: "Test", targetDate: Date(), progress: -0.5)
        #expect(underGoal.progress == 0.0)
    }

    @Test("Goal defaults to 0 progress")
    func defaultProgress() {
        let goal = Goal(title: "Test", targetDate: Date())
        #expect(goal.progress == 0.0)
    }
}

// MARK: - WallpaperStorage Tests

@Suite("Wallpaper Storage")
struct WallpaperStorageTests {

    @Test("Save, load, and delete round-trip")
    func roundTrip() {
        let testData = Data("test-wallpaper".utf8)

        WallpaperStorage.save(testData)
        let loaded = WallpaperStorage.load()
        #expect(loaded == testData)

        WallpaperStorage.delete()
        let afterDelete = WallpaperStorage.load()
        #expect(afterDelete == nil)
    }
}

// MARK: - StorageKeys Tests

@Suite("Storage Keys")
struct StorageKeysTests {

    @Test("Storage keys are non-empty strings")
    func keysAreValid() {
        #expect(!StorageKeys.userName.isEmpty)
        #expect(!StorageKeys.selectedAppearance.isEmpty)
    }
}

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
        #expect(entry.text == "Hello") // post-Plan 3: entry.text is String?, comparison still works
        #expect(entry.duration == 300)
    }

    @Test("JournalEntry initializes with mood")
    func initializesWithMood() {
        let entry = JournalEntry(date: Date(), text: "Great day", duration: 600, mood: .great)
        #expect(entry.mood == .great)
        #expect(entry.moodRaw == "great")
    }

    @Test("JournalEntry defaults to nil mood")
    func defaultsToNilMood() {
        let entry = JournalEntry(date: Date(), text: "Test", duration: 300)
        #expect(entry.mood == nil)
        #expect(entry.moodRaw == nil)
    }

    @Test("JournalEntry mood setter updates raw value")
    func moodSetterWorks() {
        let entry = JournalEntry(date: Date(), text: "Test", duration: 300)
        entry.mood = .bad
        #expect(entry.moodRaw == "bad")
        entry.mood = nil
        #expect(entry.moodRaw == nil)
    }

    @Test("JournalEntry defaults to empty tags")
    func defaultsToEmptyTags() {
        let entry = JournalEntry(date: Date(), text: "Test", duration: 300)
        #expect(entry.tags.isEmpty)
    }
}

// MARK: - Mood Tests

@Suite("Mood")
struct MoodTests {

    @Test("All moods have emoji")
    func allMoodsHaveEmoji() {
        for mood in Mood.allCases {
            #expect(!mood.emoji.isEmpty)
        }
    }

    @Test("All moods have label")
    func allMoodsHaveLabel() {
        for mood in Mood.allCases {
            #expect(!mood.label.isEmpty)
        }
    }

    @Test("Mood raw values are unique")
    func rawValuesUnique() {
        let rawValues = Mood.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test("Mood count is 5")
    func moodCount() {
        #expect(Mood.allCases.count == 5)
    }
}

// MARK: - Tag Tests

@Suite("Tag")
struct TagTests {

    @Test("Tag initializes with name")
    func initializesCorrectly() {
        let tag = Tag(name: "Personal")
        #expect(tag.name == "Personal")
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

// MARK: - Data Exporter Tests

@Suite("Data Exporter")
struct DataExporterTests {

    @Test("CSV export contains header")
    func csvContainsHeader() {
        let csv = DataExporter.exportCSV(entries: [])
        #expect(csv.hasPrefix("date,text,duration_seconds,mood,tags"))
    }

    @Test("CSV export includes entry data")
    func csvIncludesData() {
        let entry = JournalEntry(date: Date(), text: "Test entry", duration: 600, mood: .good)
        let csv = DataExporter.exportCSV(entries: [entry])
        let lines = csv.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].contains("Test entry"))
        #expect(lines[1].contains("600"))
        #expect(lines[1].contains("Good"))
    }

    @Test("CSV escapes double quotes")
    func csvEscapesQuotes() {
        let entry = JournalEntry(date: Date(), text: "She said \"hello\"", duration: 300)
        let csv = DataExporter.exportCSV(entries: [entry])
        #expect(csv.contains("\"\"hello\"\""))
    }

    @Test("JSON export produces valid data")
    func jsonProducesData() {
        let entry = JournalEntry(date: Date(), text: "Test", duration: 300, mood: .great)
        let data = DataExporter.exportJSON(entries: [entry])
        #expect(data != nil)
    }

    @Test("JSON export is valid JSON array")
    func jsonIsValidArray() {
        let entry = JournalEntry(date: Date(), text: "Test", duration: 300)
        guard let data = DataExporter.exportJSON(entries: [entry]),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            Issue.record("Failed to parse JSON")
            return
        }
        #expect(parsed.count == 1)
        #expect(parsed[0]["text"] as? String == "Test")
        #expect(parsed[0]["duration_seconds"] as? Int == 300)
    }

    @Test("JSON export includes mood when present")
    func jsonIncludesMood() {
        let entry = JournalEntry(date: Date(), text: "Test", duration: 300, mood: .okay)
        guard let data = DataExporter.exportJSON(entries: [entry]),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            Issue.record("Failed to parse JSON")
            return
        }
        #expect(parsed[0]["mood"] as? String == "okay")
    }

    @Test("JSON export omits mood when nil")
    func jsonOmitsMoodWhenNil() {
        let entry = JournalEntry(date: Date(), text: "Test", duration: 300)
        guard let data = DataExporter.exportJSON(entries: [entry]),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            Issue.record("Failed to parse JSON")
            return
        }
        #expect(parsed[0]["mood"] == nil)
    }

    @Test("Temporary file write and read round-trip")
    func tempFileRoundTrip() {
        let content = "test content"
        guard let url = DataExporter.writeToTemporaryFile(content: content, filename: "test_export.txt") else {
            Issue.record("Failed to write temp file")
            return
        }
        let read = try? String(contentsOf: url, encoding: .utf8)
        #expect(read == content)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Widget Layout Persistence Tests

@Suite("Widget Layout")
struct WidgetLayoutTests {

    @Test("WidgetItem encodes and decodes")
    func widgetItemCodable() throws {
        let widget = WidgetItem(type: .streak, size: .small)
        let data = try JSONEncoder().encode(widget)
        let decoded = try JSONDecoder().decode(WidgetItem.self, from: data)
        #expect(decoded.id == widget.id)
        #expect(decoded.type == widget.type)
        #expect(decoded.size == widget.size)
    }

    @Test("Widget array round-trips through JSON")
    func widgetArrayRoundTrip() throws {
        let widgets = [
            WidgetItem(type: .streak, size: .small),
            WidgetItem(type: .calendar, size: .medium),
            WidgetItem(type: .goals, size: .large)
        ]
        let data = try JSONEncoder().encode(widgets)
        let decoded = try JSONDecoder().decode([WidgetItem].self, from: data)
        #expect(decoded.count == 3)
        #expect(decoded[0].type == .streak)
        #expect(decoded[1].size == .medium)
        #expect(decoded[2].type == .goals)
    }
}

// MARK: - AccentColorChoice Tests

@Suite("Accent Color Choice")
struct AccentColorChoiceTests {

    @Test("All choices have labels")
    func allHaveLabels() {
        for choice in AccentColorChoice.allCases {
            #expect(!choice.label.isEmpty)
        }
    }

    @Test("All choices produce a color")
    func allProduceColors() {
        #expect(AccentColorChoice.allCases.count == 6)
    }
}

// MARK: - TextSizeChoice Tests

@Suite("Text Size Choice")
struct TextSizeChoiceTests {

    @Test("All text sizes have labels")
    func allHaveLabels() {
        for choice in TextSizeChoice.allCases {
            #expect(!choice.label.isEmpty)
        }
    }

    @Test("Text size count is 4")
    func textSizeCount() {
        #expect(TextSizeChoice.allCases.count == 4)
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
        #expect(!StorageKeys.accentColor.isEmpty)
        #expect(!StorageKeys.textSize.isEmpty)
        #expect(!StorageKeys.notificationsEnabled.isEmpty)
        #expect(!StorageKeys.notificationHour.isEmpty)
        #expect(!StorageKeys.notificationMinute.isEmpty)
        #expect(!StorageKeys.widgetLayout.isEmpty)
    }
}

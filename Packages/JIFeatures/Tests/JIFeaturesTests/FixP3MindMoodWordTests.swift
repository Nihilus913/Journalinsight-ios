import Foundation
import Testing
import JIPersistence
@testable import JIFeatures

// W-FIX-P3 RG-86 (B-24): the Mind "Today" card names the mood saved in today's check-in
// ("Mood: 🙂 Good"), not only the five-step track; no mood = no word (rule 5, never invented).

private func checkIn(_ mood: JIPersistence.Mood?) -> CheckIn {
    CheckIn(date: "2026-10-06", mood: mood, stress: 2, energy: 3, dosed: false,
            irritability: nil, restlessness: nil, appetite: nil, note: nil, updatedAt: "x")
}

@Suite struct FixP3MindMoodWordTests {
    @Test func savedMoodWordIsShown() {
        #expect(mindTodaySummary(checkIn(.good)).moodWord == "Mood: 🙂 Good")
        #expect(mindTodaySummary(checkIn(.terrible)).moodWord == "Mood: 😢 Terrible")
    }

    @Test func noMoodNoWord() {
        #expect(mindTodaySummary(checkIn(nil)).moodWord == nil)
        #expect(mindTodaySummary(nil).moodWord == nil)
    }
}

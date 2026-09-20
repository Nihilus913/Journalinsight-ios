import Testing
import Foundation
@testable import JIFeatures

@Suite struct JournalMoodPromptsTests {
    @Test func moodOrderValenceEmoji() {
        #expect(MOODS == [.great, .good, .okay, .bad, .terrible])
        #expect(moodValence(.great) == 1)
        #expect(moodValence(.okay) == 0)
        #expect(moodValence(.terrible) == -1)
        #expect(moodEmoji(.good) == "🙂")
    }

    @Test func tenPromptsTodaysThreeDeterministicByDayOfYear() {
        #expect(JournalPrompts.PROMPTS.count == 10)
        let d = JournalCalendarZurich.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let a = JournalPrompts.todaysPrompts(d)
        #expect(a.count == 3)
        #expect(JournalPrompts.todaysPrompts(d) == a)
    }
}

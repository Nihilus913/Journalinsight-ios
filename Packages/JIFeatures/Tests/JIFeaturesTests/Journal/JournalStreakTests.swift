import Testing
import Foundation
@testable import JIFeatures

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
}

@Suite struct JournalStreakTests {
    let today = date(2026, 8, 23) // Sun 2026-08-23

    @Test func currentRequiresTodayCountsBackGapsStop() {
        let r = JournalStreak.computeStreak(dates: ["2026-08-23", "2026-08-22", "2026-08-21", "2026-08-19"], today: today)
        #expect(r.current == 3)
    }

    @Test func currentIsZeroWithoutAnEntryToday() {
        #expect(JournalStreak.computeStreak(dates: ["2026-08-22", "2026-08-21"], today: today).current == 0)
    }

    @Test func bestIsLongestRunAnywhereDedupesRepeats() {
        let r = JournalStreak.computeStreak(dates: ["2026-08-01", "2026-08-02", "2026-08-02", "2026-08-03", "2026-08-10"], today: today)
        #expect(r.best == 3)
    }

    @Test func nextMilestoneIsTheNextAboveCurrent() {
        #expect(JournalStreak.MILESTONES[0] == 7)
        let r = JournalStreak.computeStreak(dates: ["2026-08-23", "2026-08-22", "2026-08-21"], today: today)
        #expect(r.nextMilestone == 7)
    }
}

@Suite struct JournalStreakMilestoneTests {
    @Test func doesNotFireBeforeFirstMilestone() {
        #expect(JournalStreak.nextUnseenMilestone(current: 6, lastCelebrated: nil) == nil)
    }

    @Test func firesTheInstantFirstMilestoneReached() {
        #expect(JournalStreak.nextUnseenMilestone(current: JournalStreak.MILESTONES[0], lastCelebrated: nil) == 7)
    }

    @Test func doesNotRefireOnRemountAtSameCelebratedStreak() {
        #expect(JournalStreak.nextUnseenMilestone(current: 7, lastCelebrated: 7) == nil)
    }

    @Test func doesNotFireBetweenMilestones() {
        #expect(JournalStreak.nextUnseenMilestone(current: 8, lastCelebrated: 7) == nil)
        #expect(JournalStreak.nextUnseenMilestone(current: 13, lastCelebrated: 7) == nil)
    }

    @Test func firesAgainOnceNextMilestoneCrossed() {
        #expect(JournalStreak.nextUnseenMilestone(current: 14, lastCelebrated: 7) == 14)
    }

    @Test func brokenStreakBelowCelebratedMilestoneDoesNotRefire() {
        #expect(JournalStreak.nextUnseenMilestone(current: 3, lastCelebrated: 7) == nil)
    }

    @Test func catchingUpMultipleMilestonesFiresOnlyHighest() {
        #expect(JournalStreak.nextUnseenMilestone(current: 20, lastCelebrated: nil) == 14)
    }

    @Test func firesTheTopMilestone() {
        #expect(JournalStreak.nextUnseenMilestone(current: 365, lastCelebrated: 200) == 365)
    }

    @Test func nothingLeftBeyondTopMilestone() {
        #expect(JournalStreak.nextUnseenMilestone(current: 1000, lastCelebrated: 365) == nil)
    }

    @Test func currentZeroNeverCelebrated() {
        #expect(JournalStreak.nextUnseenMilestone(current: 0, lastCelebrated: nil) == nil)
    }
}

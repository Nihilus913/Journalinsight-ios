import Testing
import Foundation
import JIPersistence
@testable import JIFeatures

private func e(_ id: Int64, _ date: String, _ ts: String, _ dur: Int = 300, _ mood: JIFeatures.Mood? = nil) -> Entry {
    Entry(id: id, date: date, ts: ts, text: "x", durationSec: dur, mood: mood?.rawValue, tags: [])
}

@Suite struct TimeOfDayBucketTests {
    @Test(arguments: [
        ("2026-08-01T00:00:00", JournalInsights.TimeOfDayBucket.earlyMorning),
        ("2026-08-01T06:59:00", .earlyMorning),
        ("2026-08-01T07:00:00", .morning),
        ("2026-08-01T11:59:00", .morning),
        ("2026-08-01T12:00:00", .afternoon),
        ("2026-08-01T16:59:00", .afternoon),
        ("2026-08-01T17:00:00", .evening),
        ("2026-08-01T20:59:00", .evening),
        ("2026-08-01T21:00:00", .night),
        ("2026-08-01T23:59:00", .night),
    ])
    func bucketBoundaries(ts: String, bucket: JournalInsights.TimeOfDayBucket) {
        #expect(JournalInsights.timeOfDayBucket(ts) == bucket)
    }
}

@Suite struct TimeOfDayDistributionTests {
    @Test func bucketsEachEntryIndependently() {
        let list = [
            e(1, "2026-08-01", "2026-08-01T06:00:00"),
            e(2, "2026-08-02", "2026-08-02T22:00:00"),
            e(3, "2026-08-03", "2026-08-03T09:00:00"),
        ]
        let dist = JournalInsights.timeOfDayDistribution(list)
        #expect(dist[.earlyMorning] == 1)
        #expect(dist[.morning] == 1)
        #expect((dist[.afternoon] ?? 0) == 0)
        #expect(dist[.night] == 1)
    }

    @Test func preferredTimeOfDayPicksMostPopulated() {
        let list = [
            e(1, "2026-08-01", "2026-08-01T08:00:00"),
            e(2, "2026-08-02", "2026-08-02T09:00:00"),
            e(3, "2026-08-03", "2026-08-03T09:30:00"),
            e(4, "2026-08-04", "2026-08-04T20:00:00"),
        ]
        #expect(JournalInsights.preferredTimeOfDay(list) == .morning)
    }

    @Test func tiesBreakToEarliestBucketInCanonicalOrder() {
        let list = [
            e(1, "2026-08-01", "2026-08-01T08:00:00"), // Morning
            e(2, "2026-08-02", "2026-08-02T20:00:00"), // Evening
        ]
        #expect(JournalInsights.preferredTimeOfDay(list) == .morning)
    }

    @Test func nullWithNoEntries() {
        #expect(JournalInsights.preferredTimeOfDay([]) == nil)
    }
}

@Suite struct LongestSessionSecTests {
    @Test func maxDurationAcrossEntries() {
        let list = [
            e(1, "2026-08-01", "2026-08-01T08:00:00", 300),
            e(2, "2026-08-02", "2026-08-02T08:00:00", 900),
            e(3, "2026-08-03", "2026-08-03T08:00:00", 600),
        ]
        #expect(JournalInsights.longestSessionSec(list) == 900)
    }

    @Test func zeroWithNoEntries() {
        #expect(JournalInsights.longestSessionSec([]) == 0)
    }
}

@Suite struct WeeklyStatsTests {
    private let today = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 23))! // Sun

    @Test func bucketsEntriesIntoMondayFirstWeekEmptyWeeksGetZeroRow() {
        let list = [
            e(1, "2026-08-03", "2026-08-03T08:00:00", 300),
            e(2, "2026-08-10", "2026-08-10T08:00:00", 300),
            e(3, "2026-08-11", "2026-08-11T08:00:00", 900),
        ]
        let weeks = JournalInsights.weeklyStats(list, weeks: 3, today: today)
        #expect(weeks == [
            .init(weekStart: "2026-08-03", count: 1, avgDurationMin: 5),
            .init(weekStart: "2026-08-10", count: 2, avgDurationMin: 10),
            .init(weekStart: "2026-08-17", count: 0, avgDurationMin: 0),
        ])
    }

    @Test func returnedOldestFirstEndingAtTodaysWeek() {
        let weeks = JournalInsights.weeklyStats([], weeks: 4, today: today)
        #expect(weeks.map(\.weekStart) == ["2026-07-27", "2026-08-03", "2026-08-10", "2026-08-17"])
    }

    @Test func entryOutsideRequestedWindowNotCounted() {
        let list = [e(1, "2026-01-01", "2026-01-01T08:00:00", 300)]
        let weeks = JournalInsights.weeklyStats(list, weeks: 2, today: today)
        #expect(weeks.reduce(0) { $0 + $1.count } == 0)
    }
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

// B-57 W1 fixer f3 — the pure helpers behind the Journal / Mind / Settings-family boards.
// Every value a card shows is derived here from existing stores; a missing input is "—" plus a
// reason word, never a zero.

private let zurich = JournalCalendarZurich.calendar
private func day(_ iso: String, hour: Int = 12) -> Date {
    let p = iso.split(separator: "-").compactMap { Int($0) }
    return zurich.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
}
private func entry(_ id: Int64, _ date: String, mood: String? = nil) -> Entry {
    Entry(id: id, date: date, ts: "\(date)T12:00:00Z", text: "t\(id)", durationSec: 60, mood: mood, tags: [])
}

// MARK: - Journal

@Test func journalMoodScoreMapsTheFiveMoodsOntoOneToFive() {
    #expect(journalMoodScore("great") == 5)
    #expect(journalMoodScore("okay") == 3)
    #expect(journalMoodScore("terrible") == 1)
    #expect(journalMoodScore(nil) == nil)
    #expect(journalMoodScore("unknown") == nil)
    #expect(journalMood(forScore: 4) == .good)
    #expect(journalMood(forScore: 0) == nil)
}

@Test func journalWeekDotsRunMondayToSundayAndMarkTodayOpen() {
    // 2026-09-23 is a Wednesday.
    let dots = journalWeekDots(dates: ["2026-09-21", "2026-09-22"], today: day("2026-09-23"))
    #expect(dots.map(\.initial) == ["M", "T", "W", "T", "F", "S", "S"])
    #expect(dots.map(\.written) == [true, true, false, false, false, false, false])
    #expect(dots[2].isToday)
    #expect(dots[3].isFuture)
    #expect(journalTodayWritten(dates: ["2026-09-21"], today: day("2026-09-23")) == false)
}

@Test func journalPeriodStatsCountsEntryDaysUpToTodayAndAveragesMood() {
    let entries = [entry(1, "2026-09-01", mood: "great"), entry(2, "2026-09-01", mood: "okay"),
                   entry(3, "2026-09-10", mood: "good"), entry(4, "2026-08-10", mood: "bad")]
    let s = journalPeriodStats(entries: entries, tab: .month, anchor: day("2026-09-23"), today: day("2026-09-23"))
    #expect(s.entryDays == 2)
    #expect(s.elapsedDays == 23)
    #expect(s.averageMood == 4.0)           // (5 + 3 + 4) / 3
    #expect(s.trendWord == "Up on last month")  // August averaged 2
}

@Test func journalPeriodStatsWithoutMoodsSaysNoTrendAndNeverZero() {
    let s = journalPeriodStats(entries: [], tab: .week, anchor: day("2026-09-23"), today: day("2026-09-23"))
    #expect(s.entryDays == 0)
    #expect(s.elapsedDays == 3)
    #expect(s.averageMood == nil)
    #expect(s.trendWord == "No trend yet")
    #expect(journalAverageMoodText(s.averageMood) == "—")
}

@Test func journalCalendarTitlesFollowTheTab() {
    #expect(journalCalendarTitle(.month, anchor: day("2026-09-23")) == "September")
    #expect(journalCalendarTitle(.year, anchor: day("2026-09-23")) == "2026")
    #expect(JournalCalendarTab.allCases.map(\.title) == ["Week", "Month", "Year"])
    let next = journalShiftAnchor(.year, anchor: day("2026-09-23"), dir: 1)
    #expect(zurich.component(.year, from: next) == 2027)
    #expect(journalYearMonthCounts(dates: ["2026-09-01", "2026-09-02", "2026-01-05"], year: 2026)[8] == 2)
}

// MARK: - Mind

@Test func mindTodaySummaryWithoutCheckInIsNotCheckedInAndNil() {
    let s = mindTodaySummary(nil)
    #expect(s.stress == nil && s.energy == nil && s.moodStep == nil)
    #expect(s.statusWord == "Not checked in")
}

@Test func mindTodaySummaryReadsTodaysCheckIn() {
    let c = CheckIn(date: "2026-09-23", mood: .good, stress: 2, energy: 4, dosed: false,
                    irritability: nil, restlessness: nil, appetite: nil, note: nil, updatedAt: "x")
    let s = mindTodaySummary(c)
    #expect(s.stress == 2 && s.energy == 4 && s.moodStep == 4)
    #expect(s.statusWord == "Checked in")
}

@Test func who5WordSitsEitherSideOfTheScreeningLine() {
    #expect(who5ScoreWord(pct: 72) == "Above the screening line")
    #expect(who5ScoreWord(pct: 50) == "At or below the screening line")
}

// MARK: - Local mirrors

@Test func localMirrorsSummaryCountsOnlyTheSetsThatExist() {
    let empty = localMirrorsSummary(hasGoals: false, targetCount: 0, decisionCount: nil)
    #expect(empty.total == 3)
    #expect(empty.mirrored == 0)
    #expect(empty.word == "Nothing yet")
    let partial = localMirrorsSummary(hasGoals: true, targetCount: 0, decisionCount: 2)
    #expect(partial.mirrored == 2)
    #expect(partial.word == "Partial")
    #expect(localMirrorsSummary(hasGoals: true, targetCount: 3, decisionCount: 1).word == "All mirrored")
}

// MARK: - Data quality

@Test func dataQualitySourceSummaryTakesTheWorstStatePerSource() {
    func f(_ source: String, _ metric: String, _ state: FreshnessState, stale: Int? = nil) -> FreshnessEntry {
        FreshnessEntry(source: source, dsoKey: 2, metric: metric, metricLabel: metric, state: state, lastDate: nil,
                       firstDate: nil, daysStale: stale, cadenceDays: nil, coverageChecked: true, gaps: nil,
                       gapCount: nil, totalMissingDays: nil)
    }
    let rows = [f("GarminAPI", "steps", .green), f("GarminAPI", "activity", .red, stale: 19),
                f("AppleHealth", "sleep", .green), f("YAZIO", "kcal", .amber, stale: 2)]
    let s = dataQualitySourceSummary(rows)
    #expect(s.sources.map(\.source) == ["AppleHealth", "GarminAPI", "YAZIO"])
    #expect(s.fresh == 1)
    #expect(s.stale == 2)
    #expect(s.sources.first { $0.source == "GarminAPI" }?.state == .red)
    #expect(s.sources.first { $0.source == "GarminAPI" }?.daysStale == 19)
    #expect(dataQualitySourceSummary([]).sources.isEmpty)
}

// MARK: - Backup

@Test @MainActor func backupRecordsTheLastExportAndReadsItBack() throws {
    let db = try AppDatabase.inMemory()
    let vm = BackupViewModel(db: db, cipher: IdentityCipher(), appVersion: "t", now: { day("2026-09-23") })
    #expect(vm.lastBackupAt == nil)
    vm.exportFinished(.success(URL(fileURLWithPath: "/tmp/x.json")))
    #expect(vm.lastBackupAt == day("2026-09-23"))
    let again = BackupViewModel(db: db, cipher: IdentityCipher(), appVersion: "t", now: { day("2026-09-26") })
    #expect(again.lastBackupAt == day("2026-09-23"))
    #expect(backupDaysAgoText(again.lastBackupAt, now: day("2026-09-26"), calendar: zurich) == "3 days ago")
    #expect(backupDaysAgoText(nil, now: day("2026-09-26"), calendar: zurich) == "No data")
    vm.exportFinished(.failure(CocoaError(.userCancelled)))
    #expect(vm.lastBackupAt == day("2026-09-23"))
}

// MARK: - Settings root

@Test @MainActor func settingsRootReachesEveryRegisteredSection() {
    let reachable = Set(SettingsRoot.rows.flatMap(\.sectionIds))
    for section in SettingsRegistry.sections {
        #expect(reachable.contains(section.id), "\(section.id) is not reachable from the Settings root")
    }
    #expect(SettingsRoot.headers == ["Connection", "Preferences", "Data", "Advanced"])
}

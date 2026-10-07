import Foundation
import HealthKit
import Testing
import JICore
@testable import JIHealthKit

struct FakeHistoryStore: HealthStoreWorkoutQuerying, HealthStoreHeartRateQuerying {
    let rows: [HKWorkoutRecord]
    var hr: [HeartRateReading] = []
    func allWorkouts(start: Date, end: Date) async throws -> [HKWorkoutRecord] {
        rows.filter { $0.start >= start && $0.start < end }
    }
    func heartRates(start: Date, end: Date) async throws -> [HeartRateReading] {
        hr.filter { $0.ts >= start && $0.ts <= end }
    }
}

/// W-OFFLINE2 OFF2-4: the no-hub Training history straight from HealthKit workouts.
@Suite struct HKTrainingHistoryReaderTests {
    let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Zurich")!; return c }()
    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    /// The OFF2-2 seed's shape: 2 route-less runs, 1 strength, 2 walks.
    var seeded: [HKWorkoutRecord] {[
        HKWorkoutRecord(activityType: .running, start: at(6, 7), end: at(6, 7, 40), sourceName: "JI seed", distanceM: 7_200, avgHRBpm: 151.4, maxHRBpm: 172),
        HKWorkoutRecord(activityType: .walking, start: at(5, 12), end: at(5, 12, 30), sourceName: "JI seed", distanceM: 2_400),
        HKWorkoutRecord(activityType: .traditionalStrengthTraining, start: at(4, 18), end: at(4, 18, 55), sourceName: "JI seed", avgHRBpm: 118),
        HKWorkoutRecord(activityType: .running, start: at(2, 7), end: at(2, 8, 5), sourceName: "JI seed", distanceM: 12_000, avgHRBpm: 148),
        HKWorkoutRecord(activityType: .walking, start: at(1, 17), end: at(1, 17, 45), sourceName: "JI seed", distanceM: 3_600),
    ]}

    func reader(_ store: FakeHistoryStore) -> HKTrainingHistoryReader {
        let now = at(7, 9)
        return HKTrainingHistoryReader(store: store, heartRate: store, calendar: calendar, now: { now })
    }

    @Test func fiveWorkoutsAreFiveRowsNewestFirstWithTypesDurationsAndDates() async throws {
        let rows = try await reader(FakeHistoryStore(rows: seeded.shuffled())).recentWorkouts(days: 14)
        #expect(rows.count == 5)
        #expect(rows.map(\.type) == ["running", "walking", "traditional_strength_training", "running", "walking"])
        #expect(rows.map(\.durationSec) == [2_400, 1_800, 3_300, 3_900, 2_700])
        #expect(rows[0].distanceM == 7_200 && rows[0].avgHr == 151 && rows[0].maxHr == 172)
        #expect(rows[2].distanceM == nil)                     // strength: no distance, never 0
        #expect(rows[1].avgHr == nil)                          // walk without HR: nil, never 0
        #expect(rows.allSatisfy { $0.source == "apple" })      // "Apple Health" source label
        #expect(rows.map(\.startDate) == [at(6, 7), at(5, 12), at(4, 18), at(2, 7), at(1, 17)])
        #expect(Set(rows.map(\.activityId)).count == 5)
        #expect(rows.allSatisfy { $0.activityId < 0 })        // never a hub id
    }

    @Test func windowIsLocalDaysIncludingToday() async throws {
        let rows = try await reader(FakeHistoryStore(rows: seeded)).recentWorkouts(days: 3)   // 5, 6, 7 Oct
        #expect(rows.count == 2)
    }

    @Test func dayDetailHoldsThatDaysWorkoutsOnly() async throws {
        let day = try await reader(FakeHistoryStore(rows: seeded)).trainingDay(date: "2026-10-06")
        #expect(day.date == "2026-10-06")
        #expect(day.activities.map(\.type) == ["running"])
        #expect(day.exerciseSets.isEmpty)
    }

    @Test func seriesIsHROnlyFromTheWorkoutWindow() async throws {
        var store = FakeHistoryStore(rows: seeded)
        store.hr = (0..<40).map { HeartRateReading(ts: at(6, 7, $0), bpm: 140 + Double($0)) } + [HeartRateReading(ts: at(6, 9), bpm: 60)]
        let r = reader(store)
        let run = try await r.recentWorkouts(days: 14)[0]
        let series = try await r.activitySeries(activityId: run.activityId)
        #expect(series.hrOnly)
        #expect(series.splits.isEmpty)
        #expect(series.points.count == 40)
        #expect(series.points.first == ActivitySeriesPoint(t: 0, hr: 140, paceSPerKm: nil))
        #expect(series.points.allSatisfy { $0.paceSPerKm == nil })
    }

    @Test func unknownIdIsUnavailable() async throws {
        let r = reader(FakeHistoryStore(rows: seeded))
        await #expect(throws: HKTrainingHistoryReader.SeriesUnavailable.self) { try await r.activitySeries(activityId: -1) }
    }

    @Test func noHRSamplesIsUnavailable() async throws {
        let r = reader(FakeHistoryStore(rows: seeded))
        let walk = try await r.recentWorkouts(days: 14)[1]
        await #expect(throws: HKTrainingHistoryReader.SeriesUnavailable.self) { try await r.activitySeries(activityId: walk.activityId) }
    }
}

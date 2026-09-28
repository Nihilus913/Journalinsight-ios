import Foundation
import HealthKit
import Testing
import JICore
@testable import JIHealthKit

private struct FakeWorkoutStore: HealthStoreWorkoutQuerying {
    let rows: [HKWorkoutRecord]
    func allWorkouts(start: Date, end: Date) async throws -> [HKWorkoutRecord] {
        rows.filter { $0.end > start && $0.start < end }
    }
}

@Suite struct HKTodayWorkoutsReaderTests {
    let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Zurich")!; return c }()
    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: h, minute: m))!
    }

    @Test func readsTodaysWorkoutsWithKindDurationAndSource() async throws {
        let store = FakeWorkoutStore(rows: [
            HKWorkoutRecord(activityType: .walking, start: at(28, 7), end: at(28, 7, 25), sourceName: "Apple Watch"),
            HKWorkoutRecord(activityType: .traditionalStrengthTraining, start: at(28, 17), end: at(28, 17, 52), sourceName: "Bevel"),
            HKWorkoutRecord(activityType: .running, start: at(27, 18), end: at(27, 19), sourceName: "Workout"),
        ])
        let now = at(28, 20)
        let reader = HKTodayWorkoutsReader(store: store, calendar: calendar, now: { now })
        let rows = try await reader.todayWorkouts()
        #expect(rows.count == 2)
        #expect(rows[0].kind == .cardio)
        #expect(rows[1] == TodayWorkout(kind: .strength, activityName: "Traditional strength",
                                        start: at(28, 17), end: at(28, 17, 52), sourceName: "Bevel"))
        #expect(rows[1].summary == "Traditional strength · 52 min · Bevel")
    }

    @Test func workoutStartedYesterdayIsNotToday() async throws {
        let store = FakeWorkoutStore(rows: [
            HKWorkoutRecord(activityType: .running, start: at(27, 23, 30), end: at(28, 0, 20), sourceName: "Workout"),
        ])
        let now = at(28, 9)
        #expect(try await HKTodayWorkoutsReader(store: store, calendar: calendar, now: { now }).todayWorkouts().isEmpty)
    }

    @Test func kindMapping() {
        #expect(HKTodayWorkoutsReader.kind(of: .functionalStrengthTraining) == .strength)
        for t: HKWorkoutActivityType in [.running, .cycling, .walking, .elliptical, .rowing] {
            #expect(HKTodayWorkoutsReader.kind(of: t) == .cardio)
        }
        #expect(HKTodayWorkoutsReader.kind(of: .yoga) == .other)
    }
}

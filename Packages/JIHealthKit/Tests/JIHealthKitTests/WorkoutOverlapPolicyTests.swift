import Foundation
import Testing
@testable import JIHealthKit

/// W9 L2 (B-30 P2.7, audit §4 item 7): a hub workout is skipped when another source already holds
/// a workout overlapping more than half of its duration — WHOOP/Strava/Bevel history stays
/// authoritative for its era. Pure, HK-free, so it runs on any `swift test` host.
struct WorkoutOverlapPolicyTests {
    private let zurich: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return cal
    }()
    private func at(_ h: Int, _ m: Int) -> Date {
        zurich.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: h, minute: m))!
    }
    private var whoop: DateInterval { DateInterval(start: at(9, 0), end: at(10, 0)) }

    @Test func whoopCoveringTwoThirdsOfTheHubWorkoutSkipsIt() {
        #expect(WorkoutOverlapPolicy.overlapFraction(start: at(9, 20), end: at(10, 20), existing: [whoop]) == 40.0 / 60.0)
        #expect(WorkoutOverlapPolicy.shouldSkip(start: at(9, 20), end: at(10, 20), existing: [whoop]))
    }

    @Test func whoopCoveringOneSixthOfTheHubWorkoutWritesIt() {
        #expect(WorkoutOverlapPolicy.overlapFraction(start: at(9, 50), end: at(10, 50), existing: [whoop]) == 10.0 / 60.0)
        #expect(!WorkoutOverlapPolicy.shouldSkip(start: at(9, 50), end: at(10, 50), existing: [whoop]))
    }

    @Test func exactlyHalfIsNotSkippedAndTheLargestSingleOverlapDecides() {
        // 09:30–10:30 vs WHOOP 09:00–10:00 = 30/60 = 50 % exactly -> written (rule is "> 50 %").
        #expect(!WorkoutOverlapPolicy.shouldSkip(start: at(9, 30), end: at(10, 30), existing: [whoop]))
        // Two 20-min slivers from two sources never add up to a skip; one 40-min one does.
        let slivers = [DateInterval(start: at(9, 0), end: at(9, 20)), DateInterval(start: at(9, 40), end: at(10, 0))]
        #expect(!WorkoutOverlapPolicy.shouldSkip(start: at(9, 0), end: at(10, 0), existing: slivers))
        #expect(WorkoutOverlapPolicy.shouldSkip(start: at(9, 0), end: at(10, 0), existing: slivers + [DateInterval(start: at(9, 10), end: at(9, 50))]))
    }

    @Test func noExistingWorkoutsOrAZeroDurationHubWorkoutNeverSkips() {
        #expect(!WorkoutOverlapPolicy.shouldSkip(start: at(9, 0), end: at(10, 0), existing: []))
        #expect(!WorkoutOverlapPolicy.shouldSkip(start: at(9, 0), end: at(9, 0), existing: [whoop]))
        #expect(!WorkoutOverlapPolicy.shouldSkip(start: at(10, 0), end: at(9, 0), existing: [whoop]))
    }
}

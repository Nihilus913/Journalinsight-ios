import Foundation
import Testing
import JIHub
@testable import JIHealthKit

@Suite struct BackloadMapperTests {
    @Test func mapsAllSixKinds() {
        let dto = BackloadResponseDTO(
            from: "2025-06-01", to: "2025-06-01", source: "garmin_api",
            sleep: [.init(syncId: "sleep:2025-06-01", start: "2025-06-01T22:30:00+02:00", end: "2025-06-02T06:45:00+02:00", asleepSec: 24300, deepSec: 5400, lightSec: 14400, remSec: 4500, awakeSec: 600)],
            rhr: [.init(syncId: "rhr:2025-06-01", date: "2025-06-01", bpm: 52.0)],
            steps: [.init(syncId: "steps:2025-06-01", date: "2025-06-01", count: 8421.0)],
            energy: [.init(syncId: "energy:2025-06-01", date: "2025-06-01", activeKcal: 512.0, basalKcal: 1750.0)],
            vo2max: [.init(syncId: "vo2max:2025-06-01", date: "2025-06-01", value: 47.5)],
            workouts: [.init(syncId: "workout:123", start: "2025-06-01T18:00:00+02:00", end: "2025-06-01T19:00:00+02:00", kind: .strength, name: "Full Upper", kcal: 420.0, distanceM: nil, avgHr: 128.0)]
        )

        let specs = BackloadMapper.map(dto)
        let syncIds = Set(specs.map(\.syncId))
        // sleep + rhr + steps + 2 energy (active/basal) + vo2max + workout = 7 specs
        #expect(specs.count == 7)
        #expect(syncIds.contains("sleep:2025-06-01"))
        #expect(syncIds.contains("rhr:2025-06-01"))
        #expect(syncIds.contains("steps:2025-06-01"))
        #expect(syncIds.contains("energy:2025-06-01:active"))
        #expect(syncIds.contains("energy:2025-06-01:basal"))
        #expect(syncIds.contains("vo2max:2025-06-01"))
        #expect(syncIds.contains("workout:123"))

        guard case .sleep(let s) = specs.first(where: { $0.syncId == "sleep:2025-06-01" })! else { Issue.record("expected sleep spec"); return }
        // asleepEnd = end - awakeSec
        #expect(s.asleepEnd == s.inBedEnd.addingTimeInterval(-600))

        guard case .quantity(let rhr) = specs.first(where: { $0.syncId == "rhr:2025-06-01" })! else { Issue.record("expected quantity spec"); return }
        #expect(rhr.kind == .restingHeartRate)
        #expect(rhr.value == 52.0)

        guard case .workout(let w) = specs.first(where: { $0.syncId == "workout:123" })! else { Issue.record("expected workout spec"); return }
        #expect(w.kind == .strength)
        #expect(w.kcal == 420.0)
        #expect(w.distanceM == nil)
        #expect(w.avgHr == 128.0)
    }

    @Test func workoutWithNilFieldsMapsCleanly() {
        let dto = BackloadResponseDTO(
            from: "2025-06-02", to: "2025-06-02", source: "garmin_api",
            sleep: [], rhr: [], steps: [], energy: [], vo2max: [],
            workouts: [.init(syncId: "workout:124", start: "2025-06-02T07:00:00+02:00", end: "2025-06-02T07:40:00+02:00", kind: .running, name: "Morning Run", kcal: nil, distanceM: nil, avgHr: nil)]
        )
        let specs = BackloadMapper.map(dto)
        #expect(specs.count == 1)
        guard case .workout(let w) = specs[0] else { Issue.record("expected workout spec"); return }
        #expect(w.kcal == nil)
        #expect(w.distanceM == nil)
        #expect(w.avgHr == nil)
        #expect(w.kind == .running)
    }

    @Test func unknownWorkoutKindFallsBackToOther() {
        // BackloadWorkoutKindDTO is a closed enum on the wire; this guards the mapper's own
        // fallback path (`?? .other`) rather than a currently-reachable decode failure.
        let entry = BackloadWorkoutEntryDTO(syncId: "workout:125", start: "2025-06-03T07:00:00+02:00", end: "2025-06-03T07:10:00+02:00", kind: .other, name: "Mystery", kcal: nil, distanceM: nil, avgHr: nil)
        let spec = BackloadMapper.mapWorkout(entry)
        guard case .workout(let w) = spec! else { Issue.record("expected workout spec"); return }
        #expect(w.kind == .other)
    }

    @Test func malformedDateIsDropped() {
        let entry = BackloadRHREntryDTO(syncId: "rhr:bad", date: "not-a-date", bpm: 60)
        #expect(BackloadMapper.mapRHR(entry) == nil)
    }

    @Test func dayBoundsSpanFullLocalDay() {
        let bounds = BackloadDateParsing.dayBounds("2025-06-01")
        #expect(bounds != nil)
        #expect(bounds!.end.timeIntervalSince(bounds!.start) == 86399)
    }
}

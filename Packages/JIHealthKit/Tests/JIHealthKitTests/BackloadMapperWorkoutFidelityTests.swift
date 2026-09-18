import Foundation
import Testing
import JIHub
@testable import JIHealthKit

/// W9 L1 (B-30 P3): HK-free workout-mapping rules — `raw_type`/`indoor` decode onto the spec,
/// `motorcycling*` never becomes a workout spec (a stale hub may still send it), `multi_sport`
/// maps via its child (Toby's multi_sport parents wrap a strength_training child — HT
/// `garmin.py` resolves that child for exercise sets), and the run's dense HR inside each
/// workout window rides on the spec.
struct BackloadMapperWorkoutFidelityTests {
    private func workout(_ id: String, kind: BackloadWorkoutKindDTO, rawType: String?, indoor: Bool? = nil, start: String = "2026-06-02T07:00:00+02:00", end: String = "2026-06-02T07:30:00+02:00") -> BackloadWorkoutEntryDTO {
        BackloadWorkoutEntryDTO(syncId: id, start: start, end: end, kind: kind, name: "Base", kcal: 300, distanceM: 5000, avgHr: 150, startEstimated: false, version: 7, indoor: indoor, rawType: rawType)
    }

    @Test func rawTypeAndIndoorRideOnTheSpecAndDefaultToFalse() throws {
        let treadmill = try #require(BackloadMapper.mapWorkout(workout("workout:1", kind: .running, rawType: "treadmill_running", indoor: true)))
        guard case .workout(let w) = treadmill else { Issue.record("expected workout"); return }
        #expect(w.rawType == "treadmill_running")
        #expect(w.indoor == true)
        #expect(w.kind == .running)

        let outdoor = try #require(BackloadMapper.mapWorkout(workout("workout:2", kind: .running, rawType: nil)))
        guard case .workout(let w2) = outdoor else { Issue.record("expected workout"); return }
        #expect(w2.rawType == nil)
        #expect(w2.indoor == false)
    }

    @Test func motorcyclingIsDroppedEvenWhenAStaleHubSendsIt() {
        #expect(BackloadMapper.mapWorkout(workout("workout:3", kind: .other, rawType: "motorcycling_v2")) == nil)
        #expect(BackloadMapper.mapWorkout(workout("workout:4", kind: .other, rawType: "motorcycling")) == nil)
        let dto = BackloadResponseDTO(from: "2026-06-02", to: "2026-06-02", source: "garmin_api", sleep: [], rhr: [], steps: [], energy: [], vo2max: [],
                                      workouts: [workout("workout:3", kind: .other, rawType: "motorcycling_v2"), workout("workout:5", kind: .walking, rawType: "walking")])
        #expect(BackloadMapper.map(dto).map(\.syncId) == ["workout:5"])
    }

    @Test func multiSportMapsViaItsStrengthChild() throws {
        let spec = try #require(BackloadMapper.mapWorkout(workout("workout:6", kind: .other, rawType: "multi_sport")))
        guard case .workout(let w) = spec else { Issue.record("expected workout"); return }
        #expect(w.kind == .strength)
        // an unknown raw type keeps the hub's kind
        let other = try #require(BackloadMapper.mapWorkout(workout("workout:7", kind: .other, rawType: "yoga")))
        guard case .workout(let w2) = other else { Issue.record("expected workout"); return }
        #expect(w2.kind == .other)
    }

    @Test func denseHeartRateInsideEachWindowRidesOnTheSpecAndAWorkoutWithoutHRGetsNone() {
        let hr: [BackloadHeartRateEntryDTO] = [
            .init(ts: "2026-06-02T06:59:00+02:00", bpm: 70),   // before workout:1
            .init(ts: "2026-06-02T07:00:00+02:00", bpm: 90),   // at start (inclusive)
            .init(ts: "2026-06-02T07:15:00+02:00", bpm: 150),
            .init(ts: "2026-06-02T07:30:00+02:00", bpm: 140),  // at end (inclusive)
            .init(ts: "2026-06-02T07:31:00+02:00", bpm: 120),  // after
            .init(ts: "2026-06-02T18:10:00+02:00", bpm: 110),  // inside workout:2
            .init(ts: "bogus", bpm: 99),
        ]
        let dto = BackloadResponseDTO(
            from: "2026-06-02", to: "2026-06-02", source: "garmin_api", sleep: [], rhr: [], steps: [], energy: [], vo2max: [],
            workouts: [
                workout("workout:1", kind: .running, rawType: "running"),
                workout("workout:2", kind: .strength, rawType: "strength_training", start: "2026-06-02T18:00:00+02:00", end: "2026-06-02T19:00:00+02:00"),
                workout("workout:3", kind: .walking, rawType: "walking", start: "2026-06-03T12:00:00+02:00", end: "2026-06-03T12:30:00+02:00"),
            ],
            heartRate: hr)
        let workouts: [BackloadWorkoutSampleSpec] = BackloadMapper.map(dto).compactMap { if case .workout(let w) = $0 { return w } else { return nil } }
        #expect(workouts.count == 3)
        #expect(workouts[0].hrSamples.map(\.bpm) == [90, 150, 140])
        #expect(workouts[1].hrSamples.map(\.bpm) == [110])
        #expect(workouts[2].hrSamples.isEmpty)
    }
}

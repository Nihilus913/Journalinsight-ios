import Foundation
import Testing
import JICore
@testable import JIFeatures

/// W-B38-B B-7 — the strength Live Activity's content state (exercise, set n/N, kg × reps,
/// rest countdown window, HR vs the user's limit).
@MainActor
struct StrengthSessionActivityStateTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    let capped = GateSettings(hrCapBpm: 175)

    @Test func setAndLoadLinesForARepSet() {
        let s = StrengthSessionActivityBuilder.state(
            exercise: "Barbell Bench Press", setNumber: 2, setCount: 4, weightKg: 52.5, reps: 8,
            hrBpm: 140, settings: capped, now: t0)
        #expect(s.setLine == "Set 2 of 4")
        #expect(s.loadLine == "52.5 kg × 8")
        #expect(s.hrLine == "140 / 175 bpm")
        #expect(s.capBand == .under)
        #expect(s.restEndsAt == nil)
        #expect(!s.isResting(at: t0))
    }

    @Test func timedSetShowsSecondsAndUnknownCountIsBare() {
        let s = StrengthSessionActivityBuilder.state(exercise: "Plank", setNumber: 1, setCount: nil, durationS: 45,
                                                     hrBpm: nil, settings: capped, now: t0)
        #expect(s.setLine == "Set 1")
        #expect(s.loadLine == "45 s")
        #expect(s.capBand == .unknown)   // no reading is never an all-clear
        #expect(s.hrLine == nil)
    }

    @Test func restWindowStartsNowAndEndsAfterRestSeconds() {
        let s = StrengthSessionActivityBuilder.state(exercise: "Barbell Row", setNumber: 3, setCount: 3, weightKg: 40, reps: 10,
                                                     restS: 90, hrBpm: 165, settings: capped, now: t0)
        #expect(s.restStartedAt == t0)
        #expect(s.restEndsAt == t0.addingTimeInterval(90))
        #expect(s.isResting(at: t0.addingTimeInterval(30)))
        #expect(!s.isResting(at: t0.addingTimeInterval(90)))
        #expect(s.capBand == .approaching)
    }

    @Test func overTheCapIsBreachAndNoLimitIsNoLimit() {
        let over = StrengthSessionActivityBuilder.state(exercise: "Barbell Row", setNumber: 1, hrBpm: 180, settings: capped, now: t0)
        #expect(over.capBand == .breach)
        let free = StrengthSessionActivityBuilder.state(exercise: "Barbell Row", setNumber: 1, hrBpm: 180, settings: GateSettings(), now: t0)
        #expect(free.capBand == .noLimit)
        #expect(free.limitBpm == nil)
        #expect(free.hrLine == "180 bpm")
    }

    @Test func contentStateRoundTripsThroughCodable() throws {
        let s = StrengthSessionActivityBuilder.state(exercise: "DB Shoulder Press", setNumber: 2, setCount: 3, weightKg: 12.5, reps: 10,
                                                     restS: 60, hrBpm: 150, settings: capped, now: t0)
        let back = try JSONDecoder().decode(StrengthSessionActivityState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

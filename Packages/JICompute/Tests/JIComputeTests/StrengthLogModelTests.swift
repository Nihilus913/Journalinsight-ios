import Foundation
import Testing
@testable import JICompute

/// W-B38-A A-9 — the pure strength-logger models: plate math, rest / timed-set countdown,
/// last-set defaults, and the HR cap state moved out of `SessionCoachViewModel`.
struct PlateMathTests {
    @Test func cardExampleFiftyTwoAndAHalfOnATwentyKiloBar() {
        #expect(PlateMath.perSide(totalKg: 52.5, barKg: 20, pairs: [1.25, 2.5, 5, 10]) == [10, 5, 1.25])
    }

    @Test func emptyBarIsNoPlates() {
        #expect(PlateMath.perSide(totalKg: 20, barKg: 20, pairs: [1.25, 2.5, 5, 10]) == [])
    }

    @Test func unreachableIsNil() {
        #expect(PlateMath.perSide(totalKg: 51, barKg: 20, pairs: [1.25, 2.5, 5, 10]) == nil)   // 15.5 per side
        #expect(PlateMath.perSide(totalKg: 15, barKg: 20, pairs: [10]) == nil)                 // lighter than the bar
        #expect(PlateMath.perSide(totalKg: 100, barKg: 20, pairs: [10, 5]) == nil)             // not enough plates
        #expect(PlateMath.perSide(totalKg: .nan, barKg: 20, pairs: [10]) == nil)
        #expect(PlateMath.perSide(totalKg: 40, barKg: 0, pairs: [10]) == nil)
    }

    @Test func repeatedEntriesAreMorePairsAndNonGreedyInventoriesStillSolve() {
        #expect(PlateMath.perSide(totalKg: 60, barKg: 20, pairs: [10, 10]) == [10, 10])
        // Greedy (15 first) dead-ends at 20 per side with [15, 10, 10]; 10 + 10 solves it.
        #expect(PlateMath.perSide(totalKg: 60, barKg: 20, pairs: [15, 10, 10]) == [10, 10])
    }

    @Test func defaultInventoryHasTobysMicroplates() {
        #expect(PlateMath.defaultPairs.contains(1.25))
        #expect(PlateMath.defaultPairs.contains(2.5))
        #expect(PlateMath.perSide(totalKg: 52.5, barKg: PlateMath.defaultBarKg, pairs: PlateMath.defaultPairs) == [15, 1.25])
    }
}

struct SetTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func idleHasNothingToCount() {
        let timer = SetTimer()
        #expect(timer.phase == .idle)
        #expect(timer.remainingSeconds(at: t0) == nil)
        #expect(!timer.isFinished(at: t0))
    }

    @Test func restCountsDownToZeroAndFinishes() {
        let timer = SetTimer().startingRest(seconds: 90, at: t0)
        #expect(timer.phase == .resting)
        #expect(timer.remainingSeconds(at: t0) == 90)
        #expect(timer.remainingSeconds(at: t0.addingTimeInterval(30.4)) == 60)
        #expect(!timer.isFinished(at: t0.addingTimeInterval(89)))
        #expect(timer.remainingSeconds(at: t0.addingTimeInterval(200)) == 0)
        #expect(timer.isFinished(at: t0.addingTimeInterval(90)))
    }

    @Test func timedSetCountsItsDuration() {
        let timer = SetTimer().startingTimedSet(seconds: 45, at: t0)
        #expect(timer.phase == .timedSet)
        #expect(timer.remainingSeconds(at: t0.addingTimeInterval(15)) == 30)
        #expect(timer.isFinished(at: t0.addingTimeInterval(45)))
    }

    @Test func skipAndAdjust() {
        let timer = SetTimer().startingRest(seconds: 60, at: t0)
        #expect(timer.adding(seconds: 30).remainingSeconds(at: t0) == 90)
        #expect(timer.adding(seconds: -120).remainingSeconds(at: t0) == 0)
        #expect(timer.stopped().phase == .idle)
    }

    @Test func nonPositiveDurationsNeverStart() {
        #expect(SetTimer().startingRest(seconds: 0, at: t0).phase == .idle)
        #expect(SetTimer().startingTimedSet(seconds: -5, at: t0).phase == .idle)
    }
}

struct LastSetDefaultsTests {
    func set(_ n: Int, _ reps: Int?, _ kg: Double?) -> LoggedSet {
        LoggedSet(exerciseName: "Bench press", category: nil, setNumber: n, reps: reps, weightKg: kg)
    }

    @Test func thisSessionsLastSetWinsOverEverything() {
        let d = LastSetDefaults.resolve(sessionSets: [set(1, 8, 50), set(2, 7, 52.5)], planKg: 55, planReps: 8, lastSessionSets: [set(1, 10, 40)])
        #expect(d == LastSetDefaults.Value(weightKg: 52.5, reps: 7, source: .thisSession))
    }

    @Test func planTargetBeforeLastSession() {
        let d = LastSetDefaults.resolve(sessionSets: [], planKg: 55, planReps: 8, lastSessionSets: [set(1, 10, 40)])
        #expect(d == LastSetDefaults.Value(weightKg: 55, reps: 8, source: .plan))
    }

    @Test func lastSessionFillsWhatThePlanLacks() {
        let d = LastSetDefaults.resolve(sessionSets: [], planKg: nil, planReps: nil, lastSessionSets: [set(1, 10, 40), set(2, 9, 42.5)])
        #expect(d == LastSetDefaults.Value(weightKg: 42.5, reps: 9, source: .lastSession))
        let mixed = LastSetDefaults.resolve(sessionSets: [], planKg: 60, planReps: nil, lastSessionSets: [set(1, 6, 57.5)])
        #expect(mixed == LastSetDefaults.Value(weightKg: 60, reps: 6, source: .plan))
    }

    @Test func nothingKnownIsNilNeverZero() {
        let d = LastSetDefaults.resolve(sessionSets: [], planKg: nil, planReps: nil, lastSessionSets: [])
        #expect(d == LastSetDefaults.Value(weightKg: nil, reps: nil, source: .none))
        let zero = LastSetDefaults.resolve(sessionSets: [], planKg: 0, planReps: 0, lastSessionSets: [])
        #expect(zero.weightKg == nil && zero.reps == nil)
    }
}

struct SessionCapTests {
    @Test func limitIsTheLowerOfCapAndZoneFourTop() {
        #expect(SessionCap.limitBpm(hrCapBpm: 175, zone5FloorBpm: 170) == 169)
        #expect(SessionCap.limitBpm(hrCapBpm: 160, zone5FloorBpm: 170) == 160)
        #expect(SessionCap.limitBpm(hrCapBpm: nil, zone5FloorBpm: nil) == nil)
    }

    @Test func statesAroundTheLimit() {
        #expect(SessionCap.state(hrBpm: nil, limitBpm: 170) == .unknown)
        #expect(SessionCap.state(hrBpm: 150, limitBpm: nil) == .noLimit)
        #expect(SessionCap.state(hrBpm: 150, limitBpm: 170) == .under)
        #expect(SessionCap.state(hrBpm: 155, limitBpm: 170) == .approaching)
        #expect(SessionCap.state(hrBpm: 171, limitBpm: 170) == .breach)
    }

    @Test func everyStateHasALabelAndAnAction() {
        for s in [SessionCap.State.unknown, .noLimit, .under, .approaching, .breach] {
            #expect(!SessionCap.label(for: s).isEmpty)
            #expect(!SessionCap.action(for: s, limitBpm: 170, zone5RangeText: "171–185").isEmpty)
        }
        #expect(SessionCap.action(for: .breach, limitBpm: 169, zone5RangeText: "170–185").contains("Zone 5 (170–185)"))
        #expect(!SessionCap.action(for: .breach, limitBpm: 169, zone5RangeText: nil).contains("Zone 5"))
    }
}

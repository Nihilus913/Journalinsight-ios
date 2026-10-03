import Foundation
import Testing
@testable import JIWorkouts

/// W-B38-B B-2 — the Watch strength session state machine over a fake engine (the real one is
/// `HKWorkoutSession` + `HKLiveWorkoutBuilder`; device evidence is Toby's AWU4 workout).
@MainActor
struct StrengthWorkoutSessionControllerTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func startRunsTheEngineAndMirrors() async {
        let engine = FakeStrengthWorkoutEngine()
        let c = StrengthWorkoutSessionController(engine: engine)
        #expect(c.state == .idle)
        await c.start(at: t0)
        #expect(c.state == .running)
        #expect(engine.startCount == 1)
        #expect(engine.mirrorCount == 1)
        #expect(c.isMirrored)
        #expect(c.startedAt == t0)
    }

    @Test func mirroringFailureStillRuns() async {
        let engine = FakeStrengthWorkoutEngine()
        engine.mirrorError = FakeStrengthWorkoutEngine.Failure.boom
        let c = StrengthWorkoutSessionController(engine: engine)
        await c.start(at: t0)
        #expect(c.state == .running)
        #expect(!c.isMirrored)
    }

    @Test func startFailureLeavesIdleWithAnError() async {
        let engine = FakeStrengthWorkoutEngine()
        engine.startError = FakeStrengthWorkoutEngine.Failure.boom
        let c = StrengthWorkoutSessionController(engine: engine)
        await c.start(at: t0)
        #expect(c.state == .idle)
        #expect(c.errorMessage != nil)
    }

    @Test func secondStartIsIgnored() async {
        let engine = FakeStrengthWorkoutEngine()
        let c = StrengthWorkoutSessionController(engine: engine)
        await c.start(at: t0)
        await c.start(at: t0.addingTimeInterval(5))
        #expect(engine.startCount == 1)
        #expect(c.startedAt == t0)
    }

    @Test func pauseAndResume() async {
        let engine = FakeStrengthWorkoutEngine()
        let c = StrengthWorkoutSessionController(engine: engine)
        c.pause()
        #expect(c.state == .idle) // nothing to pause
        await c.start(at: t0)
        c.pause()
        #expect(c.state == .paused)
        #expect(engine.pauseCount == 1)
        c.resume()
        #expect(c.state == .running)
        #expect(engine.resumeCount == 1)
    }

    @Test func heartRateIsForwardedWhileRunning() async {
        let engine = FakeStrengthWorkoutEngine()
        let c = StrengthWorkoutSessionController(engine: engine)
        var forwarded: [Int] = []
        c.onHeartRate = { forwarded.append($0) }
        engine.emitHeartRate(120, at: t0) // before start: dropped
        #expect(c.heartRateBpm == nil)
        await c.start(at: t0)
        engine.emitHeartRate(131.6, at: t0.addingTimeInterval(1))
        #expect(c.heartRateBpm == 132)
        #expect(forwarded == [132])
        engine.emitHeartRate(.nan, at: t0.addingTimeInterval(2)) // junk never becomes a reading
        #expect(c.heartRateBpm == 132)
        #expect(forwarded == [132])
    }

    @Test func endSavesOnceAndCarriesTheWorkoutUUID() async {
        let engine = FakeStrengthWorkoutEngine()
        let uuid = UUID()
        engine.savedUUID = uuid
        let c = StrengthWorkoutSessionController(engine: engine)
        var ended: [UUID?] = []
        c.onEnded = { ended.append($0) }
        await c.start(at: t0)
        let first = await c.end(at: t0.addingTimeInterval(600))
        let second = await c.end(at: t0.addingTimeInterval(700))
        #expect(engine.endCount == 1)
        #expect(first == uuid)
        #expect(second == uuid)
        #expect(c.hkWorkoutUUID == uuid)
        #expect(c.state == .ended)
        #expect(ended == [uuid])
    }

    @Test func endBeforeStartSavesNothing() async {
        let engine = FakeStrengthWorkoutEngine()
        let c = StrengthWorkoutSessionController(engine: engine)
        let r = await c.end(at: t0)
        #expect(r == nil)
        #expect(engine.endCount == 0)
        #expect(c.state == .idle)
    }

    @Test func heartRateAfterEndIsDropped() async {
        let engine = FakeStrengthWorkoutEngine()
        let c = StrengthWorkoutSessionController(engine: engine)
        await c.start(at: t0)
        engine.emitHeartRate(100, at: t0)
        _ = await c.end(at: t0.addingTimeInterval(60))
        engine.emitHeartRate(150, at: t0.addingTimeInterval(61))
        #expect(c.heartRateBpm == 100)
    }
}

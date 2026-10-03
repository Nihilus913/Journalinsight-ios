import Foundation
import Testing
import JICore
import JIPersistence
import JIWorkouts
@testable import JIFeatures

/// W-B38-B bridge wiring (phone side): Watch events land in the A-7 store + A-8 outbox exactly like
/// phone-logged sets; the plan down carries the A-10 prefill; the Live Activity follows the feed.
@MainActor
struct StrengthBridgeWiringTests {
    let t0 = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func watchSessionLandsInTheStoreOnceAndEndsWithoutAdvance() async throws {
        let db = try AppDatabase.inMemory()
        let store = StrengthSessionLogStore(db: db)
        let sink = StrengthBridgeStoreSink(store: store, queue: nil)
        let session = UUID()
        let start = StrengthBridgeSessionStart(sessionClientId: session, planSessionId: 4, date: "2026-10-05", startedAt: t0)
        await sink.bridgeSessionStarted(start)
        await sink.bridgeSessionStarted(start)   // replay
        let set = StrengthBridgeSet(clientId: UUID(), sessionClientId: session, exerciseKey: "Barbell Bench Press", exerciseId: 11,
                                    setIndex: 1, kind: .reps, reps: 8, weightKg: 52.5, durationS: nil, rpe: 8, performedAt: t0 + 120)
        await sink.bridgeSetLogged(set)
        var edited = set; edited.reps = 7
        await sink.bridgeSetEdited(edited)
        let sid = session.uuidString.lowercased()
        let stored = try store.sets(sessionClientId: sid)
        #expect(stored.count == 1)
        #expect(stored.first?.reps == 7)
        #expect(stored.first?.weightKg == 52.5)
        #expect(stored.first?.exerciseId == 11)
        #expect(try store.session(clientId: sid)?.sessionId == 4)

        await sink.bridgeSessionEnded(StrengthBridgeSessionEnd(sessionClientId: session, endedAt: t0 + 3600, hkWorkoutUUID: UUID()))
        #expect(try store.session(clientId: sid)?.isComplete == true)

        await sink.bridgeSetDeleted(clientId: set.clientId, sessionClientId: session)
        #expect(try store.sets(sessionClientId: sid).isEmpty)
    }

    @Test func planDownCarriesPrefillAndTheUsersLimit() {
        let lifts = [
            StrengthLogLift(exerciseId: 11, exerciseKey: "Barbell Bench Press", sets: 3, repsTarget: "8", currentKg: 50, stepKg: 2.5, nextKg: 52.5),
            StrengthLogLift(exerciseId: 12, exerciseKey: "Plank", sets: 3, repsTarget: "45s", currentKg: nil, stepKg: nil, nextKg: nil),
        ]
        let last = ["Barbell Bench Press": [StrengthSetLog(sessionClientId: "x", exerciseKey: "Barbell Bench Press", setIndex: 3, reps: 8, weightKg: 50, performedAt: "")]]
        let plan = StrengthWatchPlanBuilder.plan(date: "2026-10-05", planSessionId: 4, title: "Day 1 Upper", lifts: lifts, lastSets: last,
                                                 settings: GateSettings(hrCapBpm: 175), restS: 90)
        #expect(plan.hrLimitBpm == 175)
        #expect(plan.exercises.count == 2)
        #expect(plan.exercises[0].nextKg == 52.5)
        #expect(plan.exercises[0].targetReps == 8)
        #expect(plan.exercises[0].lastSet == StrengthWatchLastSet(weightKg: 50, reps: 8, durationS: nil))
        #expect(plan.exercises[1].kind == .timed)
        #expect(plan.exercises[1].targetDurationS == 45)
        #expect(plan.exercises[1].nextKg == nil)   // never a zero weight
    }

    @Test func activityStateFollowsTheFeedRestAndHR() {
        var now = t0
        let feed = MirroredSessionFeed(now: { now })
        feed.plan = StrengthWatchPlan(date: "2026-10-05", planSessionId: 4, title: nil, hrLimitBpm: 175, exercises: [
            StrengthWatchExercise(exerciseKey: "Barbell Bench Press", exerciseId: 11, name: "Bench press", kind: .reps, targetSets: 3,
                                  targetReps: 8, targetDurationS: nil, nextKg: 52.5, stepKg: 2.5, restS: 90, muscle: nil, lastSet: nil),
        ])
        #expect(feed.activityState(settings: GateSettings(hrCapBpm: 175), now: now) == nil)   // no mirror → no activity
        feed.mirrorStarted(at: now)
        let first = feed.activityState(settings: GateSettings(hrCapBpm: 175), now: now)
        #expect(first?.setLine == "Set 1 of 3")
        #expect(first?.loadLine == "52.5 kg × 8")
        #expect(first?.restEndsAt == nil)

        now += 60
        feed.ingest(.heartRate(bpm: 168, at: now))
        feed.ingest(.setLogged(StrengthBridgeSet(clientId: UUID(), sessionClientId: UUID(), exerciseKey: "Barbell Bench Press", exerciseId: 11,
                                                 setIndex: 1, kind: .reps, reps: 8, weightKg: 52.5, durationS: nil, rpe: nil, performedAt: now)))
        now += 30
        #expect(feed.activityState(settings: GateSettings(hrCapBpm: 175), now: now)?.capBand == .unknown)   // 30 s old HR = stale
        feed.ingest(.heartRate(bpm: 168, at: now))
        let resting = feed.activityState(settings: GateSettings(hrCapBpm: 175), now: now)
        #expect(resting?.setLine == "Set 2 of 3")
        #expect(resting?.exercise == "Bench press")
        #expect(resting?.restEndsAt == t0 + 60 + 90)
        #expect(resting?.capBand == .approaching)
        now += 120
        #expect(feed.activityState(settings: GateSettings(hrCapBpm: 175), now: now)?.restEndsAt == nil)
    }
}

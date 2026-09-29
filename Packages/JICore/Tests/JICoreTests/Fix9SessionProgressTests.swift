import Foundation
import Testing
@testable import JICore

/// W-FIX9 C-1 / G1 / G5 + audit F3: ONE completion rule (`SessionCompletion`), fed by Apple Health
/// AND the hub's `core.activity` rows, with the two parts of a combined session.
@Suite struct Fix9SessionProgressTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    func w(_ kind: TodayWorkout.Kind, _ name: String, min: Double, source: String? = "Bevel", offset: Double = 0) -> TodayWorkout {
        TodayWorkout(kind: kind, activityName: name, start: t0.addingTimeInterval(offset), end: t0.addingTimeInterval(offset + min * 60), sourceName: source)
    }
    func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    // MARK: parts of a planned session

    @Test func combinedSessionHasAStrengthAndASteadyCardioPart() {
        #expect(SessionPart.parts(of: "Day 1 Full Upper + Z2 40min") == [.strength, .steadyCardio])
        #expect(SessionPart.parts(of: "Long Z2") == [.steadyCardio])
        #expect(SessionPart.parts(of: "Norwegian 4x4 intervals") == [.intervals])
        #expect(SessionPart.parts(of: "Strength") == [.strength])
        #expect(SessionPart.parts(of: "Rest — walks only") == [])
        #expect(SessionPart.parts(of: nil) == [])
        #expect(SessionPart.parts(of: "Something else") == [])
    }

    @Test func intervalsAreTheirOwnPlannedKind() {
        #expect(PlannedSessionKind.classify("Intervals 4x4") == .interval)
        #expect(PlannedSessionKind.classify("Norwegian 4x4 intervals") == .interval)
        #expect(PlannedSessionKind.classify("Long Z2") == .cardio)
        // The hub's MODIFIED swap is the easy Z2 — a walk may complete it.
        #expect(PlannedSessionKind.classify("swap intervals for easy Z2 30-40min") == .cardio)
        #expect(SessionPart.parts(of: "swap intervals for easy Z2 30-40min") == [.steadyCardio])
    }

    // MARK: audit F3 — a walk never completes an interval day (the hub gate scores it a miss)

    @Test func aWalkDoesNotCompleteAnIntervalDay() {
        let walk = w(.cardio, "Walk", min: 40)
        #expect(SessionCompletion.resolve(planned: .interval, workouts: [walk]) == .otherActivity(walk))
        #expect(!SessionCompletion.resolve(sessionLabel: "Norwegian 4x4 intervals", workouts: [walk]).isDone)
    }

    @Test func aRunOrARideCompletesAnIntervalDay() {
        let run = w(.cardio, "Run", min: 32)
        let ride = w(.cardio, "Cycling", min: 30, offset: 7200)
        #expect(SessionCompletion.resolve(planned: .interval, workouts: [run]) == .done(run))
        #expect(SessionCompletion.resolve(sessionLabel: "Intervals 4x4", workouts: [ride]) == .done(ride))
    }

    @Test func aWalkStillCompletesAZ2Day() {
        let walk = w(.cardio, "Walk", min: 50)
        #expect(SessionCompletion.resolve(sessionLabel: "Long Z2", workouts: [walk]) == .done(walk))
    }

    // MARK: G5 — two-part progress

    @Test func strengthDoneZ2OpenIsPartial() {
        let lift = w(.strength, "Traditional strength", min: 22)
        let p = SessionCompletion.progress(sessionLabel: "Day 1 Full Upper + Z2 40min", workouts: [lift])
        #expect(p.parts.map(\.part) == [.strength, .steadyCardio])
        #expect(p.parts[0].workout == lift)
        #expect(p.parts[1].workout == nil)
        #expect(p.isPartial)
        #expect(!p.isComplete)
        #expect(p.doneParts == [.strength])
        #expect(p.openParts == [.steadyCardio])
        // The lead part (the lift) decides the NEXT "Done ·" line — unchanged from F7-1.
        #expect(p.completion == .done(lift))
    }

    @Test func bothPartsDoneIsComplete() {
        let lift = w(.strength, "Traditional strength", min: 50)
        let z2 = w(.cardio, "Cycling", min: 40, offset: 3600)
        let p = SessionCompletion.progress(sessionLabel: "Day 1 Full Upper + Z2 40min", workouts: [lift, z2])
        #expect(p.isComplete)
        #expect(!p.isPartial)
        #expect(p.lead == lift)
    }

    @Test func oneWorkoutNeverFillsTwoParts() {
        let run = w(.cardio, "Run", min: 45)
        let p = SessionCompletion.progress(sessionLabel: "Intervals 4x4 + Z2 20min", workouts: [run])
        #expect(p.doneParts.count == 1)
    }

    @Test func restDayHasNoProgress() {
        let lift = w(.strength, "Traditional strength", min: 50)
        let p = SessionCompletion.progress(sessionLabel: "Rest", workouts: [lift])
        #expect(p.parts.isEmpty)
        #expect(!p.isComplete && !p.isPartial)
        #expect(p.completion == .otherActivity(lift))
    }

    @Test func resolveBySessionLabelMatchesTheOldKindRule() {
        let lift = w(.strength, "Traditional strength", min: 52)
        let walk = w(.cardio, "Walk", min: 20, offset: -3600)
        #expect(SessionCompletion.resolve(sessionLabel: "Day 1 Full Upper + Z2 40min", workouts: [walk, lift]) == .done(lift))
        #expect(SessionCompletion.resolve(sessionLabel: "Strength", workouts: [walk]) == .otherActivity(walk))
        #expect(SessionCompletion.resolve(sessionLabel: "Strength", workouts: []) == .none)
    }

    // MARK: G1 — the hub's core.activity rows (Garmin + Apple) feed the same rule

    @Test func aGarminOnlyStrengthWorkoutCompletesTheSession() throws {
        let garmin = DayActivity(activityId: 9, type: "strength_training", name: nil, durationSec: 1500, distanceM: nil,
                                 source: "garmin", startTimeUtc: iso(t0))
        let merged = TodayWorkout.merging(local: [], hub: [garmin])
        #expect(merged.count == 1)
        let hubRow = try #require(merged.first)
        #expect(hubRow.kind == .strength)
        #expect(hubRow.sourceName == "Garmin")
        #expect(hubRow.durationMinutes == 25)
        #expect(hubRow.hubActivityId == 9)
        #expect(SessionCompletion.resolve(sessionLabel: "Day 1 Full Upper", workouts: merged).isDone)
    }

    @Test func anAppleHubRowDoesNotDoubleTheLocalHealthWorkout() {
        let local = w(.strength, "Traditional strength", min: 22)
        let sameOnHub = DayActivity(activityId: 4, type: "traditional_strength_training", name: nil, durationSec: 22 * 60,
                                    distanceM: nil, source: "apple", startTimeUtc: iso(t0.addingTimeInterval(60)))
        let merged = TodayWorkout.merging(local: [local], hub: [sameOnHub])
        #expect(merged.count == 1)
        // The phone's row keeps its app name ("Bevel") and learns its hub id (for the zone bar).
        #expect(merged.first?.sourceName == "Bevel")
        #expect(merged.first?.hubActivityId == 4)
    }

    @Test func hubRowsWithoutAStartOrOfUnknownKindStayOut() {
        let noStart = DayActivity(activityId: 1, type: "running", name: nil, durationSec: 600, distanceM: nil, source: "garmin")
        #expect(TodayWorkout.merging(local: [], hub: [noStart]).isEmpty)
        let yoga = DayActivity(activityId: 2, type: "yoga", name: nil, durationSec: 600, distanceM: nil, source: "garmin", startTimeUtc: iso(t0))
        #expect(TodayWorkout.merging(local: [], hub: [yoga]).first?.kind == .other)
    }

    @Test func hubKindsFollowTheHealthKitReader() {
        #expect(TodayWorkout.kind(ofHubType: "traditional_strength_training") == .strength)
        #expect(TodayWorkout.kind(ofHubType: "functional_strength_training") == .strength)
        #expect(TodayWorkout.kind(ofHubType: "running") == .cardio)
        #expect(TodayWorkout.kind(ofHubType: "walking") == .cardio)
        #expect(TodayWorkout.kind(ofHubType: "cycling") == .cardio)
        #expect(TodayWorkout.kind(ofHubType: "yoga") == .other)
    }

    @Test func sameWorkoutWindowIsFiveMinutes() {
        let local = w(.cardio, "Run", min: 30)
        #expect(local.isSameWorkout(startingAt: t0.addingTimeInterval(299)))
        #expect(!local.isSameWorkout(startingAt: t0.addingTimeInterval(301)))
    }

    @Test func nextStatusSaysWhichPartIsDone() {
        let run = w(.cardio, "Outdoor Run", min: 36, source: "Apple Health")
        let p = SessionCompletion.progress(sessionLabel: "Day 2 Full Upper + Z2 60min", workouts: [run])
        #expect(p.statusText == "Z2 done · Outdoor Run · 36 min · Apple Health · strength open")
        #expect(p.anyDone)
        let lift = w(.strength, "Traditional strength", min: 52)
        let q = SessionCompletion.progress(sessionLabel: "Day 2 Full Upper + Z2 60min", workouts: [lift])
        #expect(q.statusText == "Done · Traditional strength · 52 min · Bevel")
    }
}

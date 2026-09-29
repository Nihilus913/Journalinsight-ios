import Testing
import Foundation
import JICore
import JICompute
@testable import JIFeatures

/// W-FIX9 L1: Today "Completed" (C-1), NEXT done state + one verdict (C-2), aligned lift rows with
/// reps / logged vs planned / progression hint (C-3), time-in-zone bar with the Watch's bounds (C-4).
@Suite struct Fix9TodayCompletedTests {
    static let utc = TimeZone(identifier: "UTC")!
    /// 2026-09-28 20:16 UTC.
    static let end = Date(timeIntervalSince1970: 1_790_626_560)
    static let lift = TodayWorkout(kind: .strength, activityName: "Traditional strength",
                                   start: end.addingTimeInterval(-22 * 60), end: end, sourceName: "Bevel")
    static let z2 = TodayWorkout(kind: .cardio, activityName: "Cycling",
                                 start: end.addingTimeInterval(600), end: end.addingTimeInterval(600 + 40 * 60), sourceName: "Workout")
    static let session = "Day 1 Full Upper + Z2 40min"

    // MARK: C-1 the summary line

    @Test func completedSessionSaysCompletedWithTheWorkout() {
        let p = SessionCompletion.progress(sessionLabel: Self.session, workouts: [Self.lift, Self.z2])
        let t = dayTitle(verdict: verdictParts("MODIFIED — \(Self.session)"), override: nil, readiness: 71,
                         progress: p, session: Self.session, timeZone: Self.utc)
        #expect(t.word == "Completed")
        #expect(t.tone == .go)
        #expect(t.line == "Completed · Day 1 Full Upper + Z2 40min · Traditional strength · 22 min · Bevel 20:16")
    }

    @Test func strengthDoneZ2OpenSaysSo() {
        let p = SessionCompletion.progress(sessionLabel: Self.session, workouts: [Self.lift])
        let t = dayTitle(verdict: verdictParts("MODIFIED — \(Self.session)"), override: nil, readiness: 71,
                         progress: p, session: Self.session, timeZone: Self.utc)
        #expect(t.word == "Completed")
        #expect(t.tone == .go)
        #expect(t.line == "Completed strength · Z2 open · Traditional strength · 22 min · Bevel 20:16")
    }

    @Test func modifiedDayWithoutAWorkoutIsUnchanged() {
        let verdict = verdictParts("MODIFIED — \(Self.session)")
        let p = SessionCompletion.progress(sessionLabel: Self.session, workouts: [])
        let t = dayTitle(verdict: verdict, override: nil, readiness: 71, progress: p, session: Self.session, timeZone: Self.utc)
        #expect(t.line == dayTitleLine(verdict: verdict, override: nil, readiness: 71, timeZone: Self.utc))
        #expect(t.word == "Modified")
        #expect(t.tone == verdict.tone)
    }

    @Test func restDayIsUnchangedEvenWithAWorkout() {
        let verdict = verdictParts("REST — Rest")
        let p = SessionCompletion.progress(sessionLabel: "Rest day", workouts: [Self.lift])
        let t = dayTitle(verdict: verdict, override: nil, readiness: 40, progress: p, session: "Rest day", timeZone: Self.utc)
        #expect(t.word == "Rest")
        #expect(t.line == dayTitleLine(verdict: verdict, override: nil, readiness: 40, timeZone: Self.utc))
    }

    @Test func aHubGarminWorkoutCompletesTheDayToo() {
        let garmin = DayActivity(activityId: 7, type: "strength_training", name: nil, durationSec: 1500, distanceM: nil,
                                 source: "garmin", startTimeUtc: "2026-09-28T19:00:00Z")
        let p = SessionCompletion.progress(sessionLabel: "Day 1 Full Upper", workouts: TodayWorkout.merging(local: [], hub: [garmin]))
        let t = dayTitle(verdict: verdictParts("GO — Day 1 Full Upper"), override: nil, readiness: 80,
                         progress: p, session: "Day 1 Full Upper", timeZone: Self.utc)
        #expect(t.line == "Completed · Day 1 Full Upper · Strength training · 25 min · Garmin 19:25")
    }

    // MARK: C-2 NEXT: cardio vs strength, done state

    @Test func aRunDayNeverListsLiftsFromTheWeekdayFallback() {
        let plan = [Exercise(exerciseId: 1, sessionName: "Day 1 Full Upper", exerciseName: "Bench press", sets: 3,
                             repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 2, sessionId: 11)]
        let card = dayNextCard(verdict: verdictParts("GO — Long Z2 75min"), sessionForToday: "Long Z2 75min", override: nil,
                               plan: plan, weekday: 2, zones: HrZones.legacyPreW4, capBpm: nil)
        #expect(card.rows.isEmpty)
        #expect(dayNextTemplate(card: card) == .cardio)
        #expect(card.cardio?.hasPrefix("Zone 2 · 75 min") == true)
    }

    @Test func aSwapToEasyZ2ReadsAsZone2NotIntervals() {
        #expect(dayCardioLine(session: "swap intervals for easy Z2 30-40min", zones: nil, capBpm: 175) == "Zone 2 · 30–40 min · zones not set")
        #expect(dayCardioLine(session: "Norwegian 4x4 intervals", zones: nil, capBpm: 175) == "Intervals · 4 × 4 min · cap 175 bpm")
    }

    @Test func doneStateCollapsesTheCoachTextAndDropsTheOrdinal() {
        let done = dayNextDoneState(SessionCompletion.progress(sessionLabel: Self.session, workouts: [Self.lift]).completion)
        #expect(done.isDone)
        #expect(done.prescriptionLineLimit == 1)
        #expect(!done.showsOrdinal)
        let open = dayNextDoneState(.none)
        #expect(!open.isDone)
        #expect(open.prescriptionLineLimit == nil)
        #expect(open.showsOrdinal)
    }

    @Test func theDoneWorkoutsHubRowLeads() {
        let a = DayActivity(activityId: 1, type: "walking", name: nil, durationSec: 600, distanceM: nil)
        let b = DayActivity(activityId: 2, type: "traditional_strength_training", name: nil, durationSec: 1320, distanceM: nil)
        var w = Self.lift; w.hubActivityId = 2
        #expect(dayNextHubWorkouts([a, b], done: .done(w)).map(\.activityId) == [2, 1])
        #expect(dayNextHubWorkouts([a, b], done: .none).map(\.activityId) == [1, 2])
    }

    // MARK: C-3 lift rows

    static func exercise(_ id: Int, _ name: String, sets: Int?, reps: String?, kg: Double?) -> Exercise {
        Exercise(exerciseId: id, sessionName: "Day 1 Full Upper", exerciseName: name, sets: sets, repsTarget: reps,
                 currentWeightKg: kg, progressionStepKg: 2.5, weekday: 0, sessionId: 11)
    }
    static let planned = PlannedSession(id: 11, name: "Day 1 Full Upper", weekday: 0)

    @Test func heroRowsCarryRepsAndReadAsSetsTimesRepsAtKg() {
        let rows = trainingHeroRows(exercises: [Self.exercise(1, "Bench press", sets: 3, reps: "8", kg: 50),
                                                Self.exercise(2, "Pull-up", sets: 3, reps: "max", kg: 0),
                                                Self.exercise(3, "Row", sets: 3, reps: "6-12", kg: 42.5),
                                                Self.exercise(4, "Plank", sets: nil, reps: nil, kg: nil)],
                                    session: Self.planned)
        #expect(rows.map(\.prescription) == ["3 × 8 @ 50 kg", "3 × max", "3 × 6–12 @ 42.5 kg", "—"])
        // Training's own hero keeps its load text.
        #expect(rows.first?.load == "50.0 kg · 3 sets")
    }

    @Test func loggedSetsTickOrCountAgainstThePlan() {
        let rows = trainingHeroRows(exercises: [Self.exercise(1, "Bench press", sets: 3, reps: "8", kg: 50),
                                                Self.exercise(2, "Barbell row", sets: 3, reps: "8", kg: 40),
                                                Self.exercise(3, "Curl", sets: 3, reps: "10", kg: 12)],
                                    session: Self.planned)
        let sets = (1...3).map { DayExerciseSet(exerciseName: "BENCH_PRESS", exerciseCategory: nil, setNumber: $0, reps: 8, weightKg: 50) }
            + (1...2).map { DayExerciseSet(exerciseName: "Barbell Row", exerciseCategory: nil, setNumber: $0, reps: 8, weightKg: 40) }
        let out = dayNextLiftRows(rows, lifts: [], loggedSets: sets)
        #expect(out[0].right == "3 × 8 @ 50 kg ✓")
        #expect(out[0].logged == nil)
        #expect(out[1].right == "3 × 8 @ 40 kg")
        #expect(out[1].logged == "2 of 3 sets")
        #expect(out[2].logged == "0 of 3 sets")
    }

    /// Verify r1 FIX9V-1: the DB / KB / ab-roller rows read Garmin's names (prod `core.exercise_set`).
    @Test func garminNamesOfAbbreviatedLiftsCountAgainstThePlan() {
        let rows = trainingHeroRows(exercises: [Self.exercise(1, "DB Shoulder Press", sets: 3, reps: "10", kg: 12),
                                                Self.exercise(2, "DB Biceps Curl", sets: 3, reps: "10", kg: 10),
                                                Self.exercise(3, "KB Overhead Triceps Extension", sets: 3, reps: "10", kg: 12),
                                                Self.exercise(4, "Ab Roller", sets: 3, reps: "10", kg: nil)],
                                    session: Self.planned)
        func sets(_ name: String?, _ cat: String, _ n: Int) -> [DayExerciseSet] {
            (1...n).map { DayExerciseSet(exerciseName: name, exerciseCategory: cat, setNumber: $0, reps: 10, weightKg: 12) }
        }
        let logged = sets("DUMBBELL_SHOULDER_PRESS", "SHOULDER_PRESS", 3) + sets("DUMBBELL_BICEPS_CURL", "CURL", 3)
            + sets("SEATED_DUMBBELL_OVERHEAD_TRICEPS_EXTENSION", "TRICEPS_EXTENSION", 2) + sets(nil, "TRICEPS_EXTENSION", 1)
            + sets("TABLETOP_DIP", "TRICEPS_EXTENSION", 2) + sets("BARBELL_ROLLOUT", "CORE", 2)
        let out = dayNextLiftRows(rows, lifts: [], loggedSets: logged)
        #expect(out.map(\.logged) == [nil, nil, nil, "2 of 3 sets"])
        #expect(out[0].right.hasSuffix(" ✓"))
        #expect(out[2].right.hasSuffix(" ✓"))
    }

    @Test func noLoggedSetsAtAllClaimsNothing() {
        let rows = trainingHeroRows(exercises: [Self.exercise(1, "Bench press", sets: 3, reps: "8", kg: 50)], session: Self.planned)
        let out = dayNextLiftRows(rows, lifts: [], loggedSets: [])
        #expect(out[0].right == "3 × 8 @ 50 kg")
        #expect(out[0].logged == nil)
    }

    @Test func progressionHintOnlyWhereTheRuleSaysSo() {
        let rows = trainingHeroRows(exercises: [Self.exercise(1, "Bench press", sets: 3, reps: "10", kg: 50),
                                                Self.exercise(2, "Row", sets: 3, reps: "8", kg: 40)],
                                    session: Self.planned)
        let due = LiftProgression(exerciseId: 1, name: "Bench press", sessionName: "Day 1 Full Upper",
                                  currentKg: 50, nextKg: 52.5, state: .due(nextKg: 52.5), sets: 3)
        let notYet = LiftProgression(exerciseId: 2, name: "Row", sessionName: "Day 1 Full Upper",
                                     currentKg: 40, nextKg: 40, state: .notYet, sets: 3)
        let out = dayNextLiftRows(rows, lifts: [due, notYet], loggedSets: [])
        #expect(out[0].hint == "next: +2.5 kg at 3 × 10")
        #expect(out[1].hint == nil)
    }

    // MARK: C-4 time in zone, labelled with the Watch's own bounds (audit F8)

    @Test func zoneBarUsesTheWatchBoundsAndMinutes() {
        let zones = [WorkoutZoneTime(zone: 2, lowerBpm: 118, upperBpm: 135, seconds: 720),
                     WorkoutZoneTime(zone: 1, lowerBpm: nil, upperBpm: 118, seconds: 240),
                     WorkoutZoneTime(zone: 5, lowerBpm: 170, upperBpm: nil, seconds: 30),
                     WorkoutZoneTime(zone: 3, lowerBpm: 135, upperBpm: 152, seconds: 0)]
        let bar = workoutZoneBar(zones)
        #expect(bar.map(\.zone) == [1, 2, 5])
        #expect(bar.map(\.label) == ["Z1 <118 · 4 min", "Z2 118–135 · 12 min", "Z5 170+ · <1 min"])
        #expect(abs(bar.map(\.fraction).reduce(0, +) - 1) < 0.0001)
        #expect(workoutZoneBar(nil).isEmpty)
    }

    @Test func zonesDifferChipOnlyPastThreeBpm() {
        let mine = HrZones(anchor: .maxHr, anchorBpm: 198, floorsBpm: [97, 117, 139, 160, 176])
        let close = [WorkoutZoneTime(zone: 2, lowerBpm: 119, upperBpm: 141, seconds: 600)]
        let far = [WorkoutZoneTime(zone: 2, lowerBpm: 110, upperBpm: 139, seconds: 600)]
        #expect(!workoutZonesDiffer(close, from: mine))
        #expect(workoutZonesDiffer(far, from: mine))
        #expect(!workoutZonesDiffer(far, from: nil))
    }
}

import Foundation
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-FIX9 fixer (verify r1 FIX9V-2): Training reads today's workouts from the same two sources
/// as Today — Apple Health on the phone AND the hub's `core.activity` rows (Garmin, or an Apple
/// workout read on another device) — so a hub-only workout completes Training's day too.
@MainActor
struct Fix9FixerTrainingCompletionTests {
    /// Friday 2026-09-11 08:00 UTC (plan weekday 4).
    static let now = ISO8601DateFormatter().date(from: "2026-09-11T08:00:00Z")!
    static let garminLift = DayActivity(activityId: 70, type: "strength_training", name: nil, durationSec: 2700, distanceM: nil,
                                        source: "garmin", startTimeUtc: "2026-09-11T06:00:00Z")

    func makeVM(_ training: TrainingFakeProvider) -> TrainingViewModel {
        training.exerciseRows = [Exercise(exerciseId: 19, sessionName: "Day 1 Full Upper", exerciseName: "Barbell Bench Press",
                                          sets: 3, repsTarget: "8", currentWeightKg: 50, progressionStepKg: 2.5, weekday: 4, sessionId: 11)]
        training.day = TrainingDayDetail(date: "2026-09-11", activities: [Self.garminLift], exerciseSets: [])
        let vm = TrainingViewModel(provider: training, healthProvider: MockDataProvider(),
                                   cache: OfflineCache(db: try! AppDatabase.inMemory()),
                                   strengthStore: StrengthStateStore(defaults: UserDefaults(suiteName: "fix9.fixer.\(UUID().uuidString)")),
                                   now: { Self.now })
        vm.todayWorkouts = TodayWorkoutsModel(source: nil, now: { Self.now })   // nothing in Apple Health
        return vm
    }

    @Test func aHubOnlyWorkoutCompletesTrainingsDayAndWeek() async throws {
        let vm = makeVM(TrainingFakeProvider())
        await vm.load()
        try await Task.sleep(for: .milliseconds(80))
        #expect(vm.selectedDayCompletion.isDone)
        #expect(vm.selectedDayCompletion.workout?.sourceName == "Garmin")
        #expect(vm.weekSummary.days.first { $0.isToday }?.done == true)
    }

    @Test func todaysHubWorkoutStillCountsWhileAnotherDayIsSelected() async throws {
        let training = TrainingFakeProvider()
        let vm = makeVM(training)
        await vm.load()
        try await Task.sleep(for: .milliseconds(80))
        training.day = TrainingDayDetail(date: "2026-09-09", activities: [], exerciseSets: [])
        vm.selectDate("2026-09-09")
        try await Task.sleep(for: .milliseconds(80))
        #expect(vm.weekSummary.days.first { $0.isToday }?.done == true)
        #expect(vm.selectedDayCompletion == .none)   // another day: no completion claimed
    }

    @Test func noWorkoutAnywhereLeavesTheDayOpen() async throws {
        let training = TrainingFakeProvider()
        let vm = makeVM(training)
        training.day = TrainingDayDetail(date: "2026-09-11", activities: [], exerciseSets: [])
        await vm.load()
        try await Task.sleep(for: .milliseconds(80))
        #expect(!vm.selectedDayCompletion.isDone)
        #expect(vm.weekSummary.days.first { $0.isToday }?.done != true)
    }
}

/// Verify r1 FIX9V-3 (S3): one workout, one minute count — the hub row rounds like the summary.
@Suite struct Fix9FixerDurationTests {
    static let run = DayActivity(activityId: 15, type: "running", name: "Outdoor Run", durationSec: 2790, distanceM: nil,
                                 source: "apple", startTimeUtc: "2026-09-29T04:12:00Z",
                                 zoneTime: [WorkoutZoneTime(zone: 2, lowerBpm: 118, upperBpm: 135, seconds: 1650)])

    @Test func theHubRowSaysTheSameMinutesAsTheSummary() {
        let w = TodayWorkout(hubActivity: Self.run)!
        #expect(w.durationMinutes == 47)
        #expect(completedWorkoutRowText(Self.run).metrics.first == "47 min")
        #expect(completedWorkoutRowText(Self.run).zones == ["Z2 28 min"])   // 27.5 min rounds, too
        #expect(workoutZoneBar(Self.run.zoneTime!).first?.label == "Z2 118–135 · 28 min")
    }
}

/// Verify r1 FIX9V-4 (S3): the workout is named once on NEXT — when the hub row that completed the
/// session leads the card, the tick line says "Done" and the row names it.
@Suite struct Fix9FixerDoneLineTests {
    static let run = Fix9FixerDurationTests.run

    @Test func theDoneLineDropsTheWorkoutWhenItsHubRowLeads() {
        let w = TodayWorkout(hubActivity: Self.run)!
        let p = SessionCompletion.progress(sessionLabel: "swap intervals for easy Z2 30-40min", workouts: [w])
        #expect(dayNextDoneLine(p, hubWorkouts: [Self.run]) == "Done")
        #expect(dayNextDoneLine(p, hubWorkouts: []) == "Done · Outdoor Run · 47 min · Apple Health")
    }

    @Test func aPhoneOnlyWorkoutStillNamesItself() {
        let local = TodayWorkout(kind: .strength, activityName: "Traditional strength", start: Date(timeIntervalSince1970: 0),
                                 end: Date(timeIntervalSince1970: 52 * 60), sourceName: "Bevel")
        let p = SessionCompletion.progress(sessionLabel: "Day 1 Full Upper", workouts: [local])
        #expect(dayNextDoneLine(p, hubWorkouts: [Self.run]) == "Done · Traditional strength · 52 min · Bevel")
        #expect(dayNextDoneLine(SessionCompletion.progress(sessionLabel: "Day 1 Full Upper", workouts: []), hubWorkouts: []) == nil)
    }
}

import Foundation
import SwiftUI
import Testing
import JICore
import JIPersistence
@testable import JIFeatures

/// W-B81 A-5: completed Apple workouts, read from the hub (`/training/day/{date}`), on Training + Today.
@Suite struct B81CompletedWorkoutTests {
    let outdoorRun = DayActivity(activityId: 900_002, type: "running", name: "Outdoor Run", durationSec: 2412, distanceM: 6020.5,
                                 source: "apple", avgHr: 151, maxHr: 178, sessionLoad: 241.2,
                                 startTimeUtc: "2026-09-28T05:02:04+00:00")

    @Test func appleRunRowShowsDurationDistanceAndHeartRate() {
        let t = completedWorkoutRowText(outdoorRun)
        #expect(t.title == "Outdoor Run")
        #expect(t.sourceLabel == "Apple Health")
        #expect(t.systemImage == "figure.run")
        #expect(t.metrics == ["40 min", "6.02 km", "avg 151 bpm"])
        #expect(t.accessibilityLabel == "Outdoor Run, Apple Health, 40 minutes, 6.02 kilometres, average heart rate 151 beats per minute")
    }

    @Test func missingValuesAreOmittedNeverZero() {
        // Rule 5: a strength workout with no distance and no HR shows its duration only — never "0 km".
        let lift = DayActivity(activityId: 3, type: "traditional_strength_training", name: nil, durationSec: 3120,
                               distanceM: 0, source: "apple", avgHr: nil)
        let t = completedWorkoutRowText(lift)
        #expect(t.title == "Traditional strength training")
        #expect(t.systemImage == "dumbbell")
        #expect(t.metrics == ["52 min"])
        let empty = completedWorkoutRowText(DayActivity(activityId: 4, type: "walking", name: "Walk", durationSec: nil, distanceM: nil))
        #expect(empty.metrics.isEmpty)
        #expect(empty.sourceLabel == nil)                      // older hub: no source key → no source claim
    }

    @Test func garminRowsSayGarminAndLongWorkoutsReadHours() {
        let ride = DayActivity(activityId: 5, type: "cycling", name: "Ride", durationSec: 3900, distanceM: 30_400, source: "garmin", avgHr: 132)
        let t = completedWorkoutRowText(ride)
        #expect(t.sourceLabel == "Garmin")
        #expect(t.systemImage == "figure.outdoor.cycle")
        #expect(t.metrics == ["1 h 05 min", "30.40 km", "avg 132 bpm"])
    }

    /// W-FIX10 R-03: VoiceOver says "1 hour", not "1 hours 0 minutes".
    @Test func spokenDurationUsesTheDurationFormatter() {
        let hour = DayActivity(activityId: 6, type: "running", name: "Run", durationSec: 3600, distanceM: nil, source: "apple")
        #expect(completedWorkoutRowText(hour).accessibilityLabel == "Run, Apple Health, 1 hour")
        let ride = DayActivity(activityId: 5, type: "cycling", name: "Ride", durationSec: 3900, distanceM: nil, source: "garmin")
        #expect(completedWorkoutRowText(ride).accessibilityLabel == "Ride, Garmin, 1 hour, 5 minutes")
        #expect(spokenWorkoutDuration(minutes: 1) == "1 minute")
        #expect(spokenWorkoutDuration(minutes: 125) == "2 hours, 5 minutes")
        #expect(!completedWorkoutRowText(hour).accessibilityLabel.contains("0 minutes"))
    }

    /// W-FIX10 R-02: rows in start order, not activity_id order; no start → last.
    @Test func trainingDayListsWorkoutsByStartTime() throws {
        let late = DayActivity(activityId: 1, type: "walking", name: "Walk", durationSec: nil, distanceM: nil, startTimeUtc: "2026-09-28T17:00:00+00:00")
        let early = DayActivity(activityId: 9, type: "running", name: "Run", durationSec: nil, distanceM: nil, startTimeUtc: "2026-09-28T05:02:04+00:00")
        let unknown = DayActivity(activityId: 2, type: "yoga", name: "Yoga", durationSec: nil, distanceM: nil, startTimeUtc: nil)
        let mid = DayActivity(activityId: 3, type: "cycling", name: "Ride", durationSec: nil, distanceM: nil, startTimeUtc: "2026-09-28T09:30:00.500+00:00")
        #expect(completedWorkoutsInStartOrder([late, unknown, early, mid]).map(\.activityId) == [9, 3, 1, 2])
        let src = try String(contentsOf: packageRoot().appendingPathComponent("Sources/JIFeatures/Training/TrainingDayDetailCard.swift"), encoding: .utf8)
        #expect(src.contains("completedWorkoutsInStartOrder(detail?.activities"))
    }

    @Test func timeInZoneListsOnlyZonesWithTime() {
        var run = outdoorRun
        run.zoneTime = [WorkoutZoneTime(zone: 1, lowerBpm: 0, upperBpm: 125, seconds: 240),
                        WorkoutZoneTime(zone: 2, lowerBpm: 125, upperBpm: 140, seconds: 0),
                        WorkoutZoneTime(zone: 3, lowerBpm: 140, upperBpm: 155, seconds: 910)]
        #expect(completedWorkoutRowText(run).zones == ["Z1 4 min", "Z3 15 min"])
        #expect(completedWorkoutRowText(outdoorRun).zones.isEmpty)   // pre-iOS 27 / hub without it: no line
    }

    @Test func aHealthWorkoutTheHubAlreadyHoldsIsNotListedTwice() {
        // One source of truth: once the hub has the Apple workout (start ± 5 min), the phone-local row goes.
        let start = Date(timeIntervalSince1970: 1_790_571_724)
        let sameRun = TodayWorkout(kind: .cardio, activityName: "Run", start: start.addingTimeInterval(90),
                                   end: start.addingTimeInterval(2500), sourceName: "Workout")
        let laterWalk = TodayWorkout(kind: .cardio, activityName: "Walk", start: start.addingTimeInterval(4 * 3600),
                                     end: start.addingTimeInterval(4 * 3600 + 1800), sourceName: "Workout")
        #expect(healthWorkoutsNotOnHub([sameRun, laterWalk], hub: [outdoorRun]) == [laterWalk])
        // A Garmin row never hides a Health workout (the hub's own overlap rule decides those).
        var garmin = outdoorRun; garmin.source = "garmin"
        #expect(healthWorkoutsNotOnHub([sameRun], hub: [garmin]) == [sameRun])
        #expect(healthWorkoutsNotOnHub([sameRun], hub: []) == [sameRun])
    }

    @Test func metricsStackAtAccessibilitySizes() {
        #expect(!completedWorkoutMetricsStacked(.large))
        #expect(completedWorkoutMetricsStacked(.accessibility3))
    }

    @Test func trainingDayCardUsesTheCompletedWorkoutRow() throws {
        let src = try String(contentsOf: packageRoot().appendingPathComponent("Sources/JIFeatures/Training/TrainingDayDetailCard.swift"), encoding: .utf8)
        #expect(src.contains("CompletedWorkoutRow(activity:"))
        #expect(src.contains("healthWorkoutsNotOnHub("))
    }

    @Test @MainActor func todayLoadsTodaysHubWorkoutsFromTheTrainingDayRoute() async {
        let cache = OfflineCache(db: try! AppDatabase.inMemory())
        let now = { Date(timeIntervalSince1970: 1_790_582_400) }   // 2026-09-28 08:00 UTC
        let model = TodayViewModel(provider: DayStub(date: "2026-09-28", activities: [outdoorRun]), cache: cache, now: now)
        await model.load()
        #expect(model.hubWorkouts == [outdoorRun])
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}

/// The mock hub, except `/training/day/{date}` answers `activities` for `date` only.
private struct DayStub: HealthDataProvider, TrainingProviding {
    let date: String
    let activities: [DayActivity]
    let base = MockDataProvider()
    var capabilities: DataCapability { base.capabilities }
    func health() async throws -> HealthResponse { try await base.health() }
    func gate(windowDays: Int) async throws -> GateResponse { try await base.gate(windowDays: windowDays) }
    func morning() async throws -> MorningResponse { try await base.morning() }
    func morningVerdict(date: String) async throws -> MorningVerdict { try await base.morningVerdict(date: date) }
    func recovery(windowDays: Int) async throws -> [RecoveryDay] { try await base.recovery(windowDays: windowDays) }
    func syncStatus() async throws -> SyncStatus { try await base.syncStatus() }
    func trainingDay(date: String) async throws -> TrainingDayDetail {
        TrainingDayDetail(date: date, activities: date == self.date ? activities : [], exerciseSets: [])
    }
    func exercises() async throws -> [Exercise] { try await base.exercises() }
    func updateExercise(exerciseId: Int, patch: ExerciseUpdate) async throws -> ExerciseUpdateResult {
        try await base.updateExercise(exerciseId: exerciseId, patch: patch)
    }
}

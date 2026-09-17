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

    // MARK: - v2

    @Test func sleepWithoutStagesStillMapsToGenericAsleepSpec() {
        let entry = BackloadSleepEntryDTO(syncId: "sleep:2026-06-01", start: "2026-06-01T22:30:00+02:00", end: "2026-06-02T06:45:00+02:00", asleepSec: 24300, deepSec: 5400, lightSec: 14400, remSec: 4500, awakeSec: 600, stages: [])
        let specs = BackloadMapper.mapSleep(entry)
        #expect(specs.count == 1)
        guard case .sleep(let s) = specs[0] else { Issue.record("expected .sleep"); return }
        #expect(s.syncId == "sleep:2026-06-01")
    }

    @Test func sleepWithStagesEmitsDeletePlusStagedSpecInsteadOfGenericAsleep() {
        let entry = BackloadSleepEntryDTO(
            syncId: "sleep:2026-06-01", start: "2026-06-01T22:30:00+02:00", end: "2026-06-02T06:45:00+02:00",
            asleepSec: 24300, deepSec: 5400, lightSec: 14400, remSec: 4500, awakeSec: 600,
            stages: [
                .init(stage: .light, start: "2026-06-01T22:30:00+02:00", end: "2026-06-02T00:00:00+02:00"),
                .init(stage: .deep, start: "2026-06-02T00:00:00+02:00", end: "2026-06-02T01:30:00+02:00"),
                .init(stage: .rem, start: "2026-06-02T01:30:00+02:00", end: "2026-06-02T02:00:00+02:00"),
                .init(stage: .awake, start: "2026-06-02T02:00:00+02:00", end: "2026-06-02T02:05:00+02:00"),
            ])
        let specs = BackloadMapper.mapSleep(entry)
        #expect(specs.count == 2)
        guard case .delete(let kind, let syncId) = specs[0] else { Issue.record("expected .delete first"); return }
        #expect(kind == .sleepCategory)
        #expect(syncId == "sleep:2026-06-01:asleep")
        guard case .sleepStaged(let staged) = specs[1] else { Issue.record("expected .sleepStaged"); return }
        #expect(staged.baseSyncId == "sleep:2026-06-01")
        #expect(staged.stages.count == 4)
        #expect(staged.stages.map(\.stage) == [.light, .deep, .rem, .awake])
        #expect(staged.stages.map(\.syncId) == ["sleep:2026-06-01:st0", "sleep:2026-06-01:st1", "sleep:2026-06-01:st2", "sleep:2026-06-01:st3"])
    }

    @Test func stepsWithBucketsForThatDateAreDeletedNotWritten() {
        let steps = [BackloadStepsEntryDTO(syncId: "steps:2026-06-01", date: "2026-06-01", count: 8000)]
        let buckets = [BackloadStepBucketEntryDTO(syncId: "steps:2026-06-01:0000", start: "2026-06-01T00:00:00+02:00", end: "2026-06-01T00:15:00+02:00", count: 40)]
        let specs = BackloadMapper.mapSteps(steps, stepBuckets: buckets)
        #expect(specs.count == 1)
        guard case .delete(let kind, let syncId) = specs[0] else { Issue.record("expected .delete"); return }
        #expect(kind == .stepQuantity)
        #expect(syncId == "steps:2026-06-01")
    }

    @Test func stepsWithoutBucketsForThatDateAreWrittenAsBefore() {
        let steps = [BackloadStepsEntryDTO(syncId: "steps:2026-06-02", date: "2026-06-02", count: 8000)]
        let specs = BackloadMapper.mapSteps(steps, stepBuckets: [])
        #expect(specs.count == 1)
        guard case .quantity(let q) = specs[0] else { Issue.record("expected .quantity"); return }
        #expect(q.kind == .stepCount)
        #expect(q.value == 8000)
    }

    @Test func stepBucketMapsToQuantitySpecWithOwnSyncId() {
        let bucket = BackloadStepBucketEntryDTO(syncId: "steps:2026-06-01:0000", start: "2026-06-01T00:00:00+02:00", end: "2026-06-01T00:15:00+02:00", count: 40)
        let spec = BackloadMapper.mapStepBucket(bucket)
        guard case .quantity(let q) = spec! else { Issue.record("expected .quantity"); return }
        #expect(q.kind == .stepCount)
        #expect(q.syncId == "steps:2026-06-01:0000")
        #expect(q.value == 40)
    }

    @Test func heartRateRespirationSpo2DeriveSyncIdFromTimestamp() {
        let hr = BackloadMapper.mapHeartRate(.init(ts: "2026-06-01T22:31:00+02:00", bpm: 58))
        guard case .quantity(let hrq) = hr! else { Issue.record("expected .quantity"); return }
        #expect(hrq.kind == .heartRate)
        #expect(hrq.syncId == "hr:2026-06-01T22:31:00+02:00")
        #expect(hrq.value == 58)

        let resp = BackloadMapper.mapRespiration(.init(ts: "2026-06-01T22:31:00+02:00", brpm: 14))
        guard case .quantity(let respq) = resp! else { Issue.record("expected .quantity"); return }
        #expect(respq.kind == .respiratoryRate)
        #expect(respq.syncId == "resp:2026-06-01T22:31:00+02:00")

        let spo2 = BackloadMapper.mapSpo2(.init(ts: "2026-06-01T22:31:00+02:00", pct: 96))
        guard case .quantity(let spo2q) = spo2! else { Issue.record("expected .quantity"); return }
        #expect(spo2q.kind == .oxygenSaturation)
        #expect(spo2q.syncId == "spo2:2026-06-01T22:31:00+02:00")
        // written as a 0-1 fraction, not the wire's 0-100 percent
        #expect(spo2q.value == 0.96)
    }

    @Test func hrvMapsEachReadingWhenPresent() {
        let entry = BackloadHrvEntryDTO(syncId: "hrv:2026-06-01", date: "2026-06-01", nightlyRmssdMs: 42.0, readings: [
            .init(ts: "2026-06-01T23:00:00+02:00", rmssdMs: 40.0),
            .init(ts: "2026-06-01T23:05:00+02:00", rmssdMs: 44.0),
        ])
        let specs = BackloadMapper.mapHrv(entry)
        #expect(specs.count == 2)
        for spec in specs {
            guard case .quantity(let q) = spec else { Issue.record("expected .quantity"); continue }
            #expect(q.kind == .hrvSDNN)
        }
        #expect(specs.map(\.syncId) == ["hrv:2026-06-01:2026-06-01T23:00:00+02:00", "hrv:2026-06-01:2026-06-01T23:05:00+02:00"])
    }

    @Test func hrvFallsBackToNightlyAverageWhenNoReadings() {
        let entry = BackloadHrvEntryDTO(syncId: "hrv:2026-06-01", date: "2026-06-01", nightlyRmssdMs: 42.0, readings: [])
        let specs = BackloadMapper.mapHrv(entry)
        #expect(specs.count == 1)
        guard case .quantity(let q) = specs[0] else { Issue.record("expected .quantity"); return }
        #expect(q.kind == .hrvSDNN)
        #expect(q.syncId == "hrv:2026-06-01")
        #expect(q.value == 42.0)
    }

    @Test func hrvWithNeitherReadingsNorNightlyAvgMapsToNothing() {
        let entry = BackloadHrvEntryDTO(syncId: "hrv:2026-06-01", date: "2026-06-01", nightlyRmssdMs: nil, readings: [])
        #expect(BackloadMapper.mapHrv(entry).isEmpty)
    }

    @Test func dailyRespSkippedWhenDenseRespirationExistsForThatDate() {
        let dto = BackloadResponseDTO(
            from: "2026-06-01", to: "2026-06-01", source: "garmin_api",
            sleep: [], rhr: [], steps: [], energy: [], vo2max: [], workouts: [],
            respiration: [.init(ts: "2026-06-01T10:00:00+02:00", brpm: 15)],
            dailyResp: [.init(syncId: "resp:2026-06-01", date: "2026-06-01", wakingAvg: 15.0, sleepAvg: 12.0)])
        let specs = BackloadMapper.map(dto)
        #expect(!specs.contains { $0.syncId == "resp:2026-06-01" })
    }

    @Test func dailyRespWrittenAtSleepMidpointWhenNoDenseSamplesExist() {
        let dto = BackloadResponseDTO(
            from: "2026-06-01", to: "2026-06-01", source: "garmin_api",
            sleep: [.init(syncId: "sleep:2026-06-01", start: "2026-06-01T22:00:00+02:00", end: "2026-06-02T06:00:00+02:00", asleepSec: 28000, deepSec: 0, lightSec: 0, remSec: 0, awakeSec: 800)],
            rhr: [], steps: [], energy: [], vo2max: [], workouts: [],
            dailyResp: [.init(syncId: "resp:2026-06-01", date: "2026-06-01", wakingAvg: 15.0, sleepAvg: 12.0)])
        let specs = BackloadMapper.map(dto)
        guard case .quantity(let q) = specs.first(where: { $0.syncId == "resp:2026-06-01" })! else { Issue.record("expected .quantity"); return }
        #expect(q.kind == .respiratoryRate)
        #expect(q.value == 12.0) // prefers sleep_avg over waking_avg
        // sleep midpoint of 22:00 -> 06:00 is 02:00
        var zurich = Calendar(identifier: .gregorian); zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let comps = zurich.dateComponents([.hour, .minute], from: q.start)
        #expect(comps.hour == 2 && comps.minute == 0)
    }

    @Test func dailySpo2ConvertsPercentToFractionAndUsesSleepMidpoint() {
        let dto = BackloadResponseDTO(
            from: "2026-06-01", to: "2026-06-01", source: "garmin_api",
            sleep: [.init(syncId: "sleep:2026-06-01", start: "2026-06-01T22:00:00+02:00", end: "2026-06-02T06:00:00+02:00", asleepSec: 28000, deepSec: 0, lightSec: 0, remSec: 0, awakeSec: 800)],
            rhr: [], steps: [], energy: [], vo2max: [], workouts: [],
            dailySpo2: [.init(syncId: "spo2:2026-06-01", date: "2026-06-01", sleepAvg: 95.0)])
        let specs = BackloadMapper.map(dto)
        guard case .quantity(let q) = specs.first(where: { $0.syncId == "spo2:2026-06-01" })! else { Issue.record("expected .quantity"); return }
        #expect(q.kind == .oxygenSaturation)
        #expect(q.value == 0.95)
    }

    @Test func workoutStartEstimatedDefaultsFalseAndPassesThroughWhenTrue() {
        let real = BackloadWorkoutEntryDTO(syncId: "workout:1", start: "2026-06-01T18:00:00+02:00", end: "2026-06-01T19:00:00+02:00", kind: .strength, name: "Full Upper", kcal: nil, distanceM: nil, avgHr: nil)
        guard case .workout(let w1) = BackloadMapper.mapWorkout(real)! else { Issue.record("expected .workout"); return }
        #expect(w1.startEstimated == false)

        let estimated = BackloadWorkoutEntryDTO(syncId: "workout:2", start: "2026-06-01T12:00:00+02:00", end: "2026-06-01T13:00:00+02:00", kind: .running, name: "Run", kcal: nil, distanceM: nil, avgHr: nil, startEstimated: true)
        guard case .workout(let w2) = BackloadMapper.mapWorkout(estimated)! else { Issue.record("expected .workout"); return }
        #expect(w2.startEstimated == true)
    }

    @Test func mapFullV2ResponseProducesEveryKind() {
        let dto = BackloadResponseDTO(
            from: "2026-06-01", to: "2026-06-01", source: "garmin_api",
            sleep: [.init(syncId: "sleep:2026-06-01", start: "2026-06-01T22:00:00+02:00", end: "2026-06-02T06:00:00+02:00", asleepSec: 28000, deepSec: 5000, lightSec: 15000, remSec: 4000, awakeSec: 800,
                          stages: [.init(stage: .light, start: "2026-06-01T22:00:00+02:00", end: "2026-06-01T23:00:00+02:00")])],
            rhr: [.init(syncId: "rhr:2026-06-01", date: "2026-06-01", bpm: 50)],
            steps: [.init(syncId: "steps:2026-06-01", date: "2026-06-01", count: 9000)],
            energy: [.init(syncId: "energy:2026-06-01", date: "2026-06-01", activeKcal: 500, basalKcal: 1700)],
            vo2max: [.init(syncId: "vo2max:2026-06-01", date: "2026-06-01", value: 48)],
            workouts: [.init(syncId: "workout:1", start: "2026-06-01T18:00:00+02:00", end: "2026-06-01T19:00:00+02:00", kind: .strength, name: "Full Upper", kcal: nil, distanceM: nil, avgHr: nil)],
            heartRate: [.init(ts: "2026-06-01T22:31:00+02:00", bpm: 58)],
            respiration: [.init(ts: "2026-06-01T22:31:00+02:00", brpm: 14)],
            spo2: [.init(ts: "2026-06-01T22:31:00+02:00", pct: 96)],
            hrv: [.init(syncId: "hrv:2026-06-01", date: "2026-06-01", nightlyRmssdMs: 42, readings: [.init(ts: "2026-06-01T23:00:00+02:00", rmssdMs: 40)])],
            stepBuckets: [.init(syncId: "steps:2026-06-01:0000", start: "2026-06-01T00:00:00+02:00", end: "2026-06-01T00:15:00+02:00", count: 40)],
            dailyResp: [], dailySpo2: [])
        let specs = BackloadMapper.map(dto)
        let syncIds = Set(specs.map(\.syncId))
        #expect(syncIds.contains("sleep:2026-06-01:asleep"))   // the delete
        #expect(syncIds.contains("sleep:2026-06-01"))          // the staged spec
        #expect(syncIds.contains("rhr:2026-06-01"))
        #expect(syncIds.contains("steps:2026-06-01"))          // deleted (bucket exists for date)
        #expect(syncIds.contains("energy:2026-06-01:active"))
        #expect(syncIds.contains("vo2max:2026-06-01"))
        #expect(syncIds.contains("workout:1"))
        #expect(syncIds.contains("hr:2026-06-01T22:31:00+02:00"))
        #expect(syncIds.contains("resp:2026-06-01T22:31:00+02:00"))
        #expect(syncIds.contains("spo2:2026-06-01T22:31:00+02:00"))
        #expect(syncIds.contains("hrv:2026-06-01:2026-06-01T23:00:00+02:00"))
        #expect(syncIds.contains("steps:2026-06-01:0000"))
    }
}

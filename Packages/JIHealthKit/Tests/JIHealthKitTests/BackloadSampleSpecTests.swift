#if canImport(HealthKit)
import Foundation
import Testing
import HealthKit
@testable import JIHealthKit

/// W9.5 L2: direct coverage for `BackloadSampleSpec.swift` — every quantity kind's HK type + unit
/// (incl. the W9 daily kinds), the workout spec's v5 fields, and the sync-id derivations the
/// writer stamps as `HKMetadataKeySyncIdentifier`.
@Suite struct BackloadSampleSpecTests {
    static let allKinds: [BackloadQuantityKind] = [
        .restingHeartRate, .stepCount, .activeEnergyBurned, .basalEnergyBurned, .vo2Max,
        .heartRate, .respiratoryRate, .oxygenSaturation, .hrvRMSSD, .flightsClimbed, .distanceWalkingRunning,
    ]

    private let t0 = Date(timeIntervalSince1970: 1_758_000_000)

    @Test func everyKindMapsToTheRightQuantityType() {
        let expected: [(BackloadQuantityKind, HKQuantityTypeIdentifier)] = [
            (.restingHeartRate, .restingHeartRate), (.stepCount, .stepCount),
            (.activeEnergyBurned, .activeEnergyBurned), (.basalEnergyBurned, .basalEnergyBurned),
            (.vo2Max, .vo2Max), (.heartRate, .heartRate), (.respiratoryRate, .respiratoryRate),
            (.oxygenSaturation, .oxygenSaturation),
            (.flightsClimbed, .flightsClimbed), (.distanceWalkingRunning, .distanceWalkingRunning),
        ]
        for (kind, id) in expected {
            #expect(HealthKitBackloader.quantityType(kind) == HKQuantityType(id), "\(kind)")
        }
        // hrvRMSSD resolves only through HKReadKind (nil on a runtime without the native type).
        #expect(HealthKitBackloader.quantityType(.hrvRMSSD) == HKReadKind.hrvRMSSDQuantityType)
    }

    @Test func everyKindHasAUnitCompatibleWithItsType() {
        for kind in Self.allKinds {
            guard let type = HealthKitBackloader.quantityType(kind) else { continue }
            let unit = HealthKitBackloader.quantityUnit(kind)
            #expect(type.is(compatibleWith: unit), "\(kind) unit \(unit) incompatible with \(type.identifier)")
        }
    }

    @Test func unitsMatchTheHubContract() {
        #expect(HealthKitBackloader.quantityUnit(.flightsClimbed) == .count())
        #expect(HealthKitBackloader.quantityUnit(.stepCount) == .count())
        #expect(HealthKitBackloader.quantityUnit(.distanceWalkingRunning) == .meter())
        #expect(HealthKitBackloader.quantityUnit(.activeEnergyBurned) == .kilocalorie())
        #expect(HealthKitBackloader.quantityUnit(.basalEnergyBurned) == .kilocalorie())
        #expect(HealthKitBackloader.quantityUnit(.oxygenSaturation) == .percent())
        #expect(HealthKitBackloader.quantityUnit(.hrvRMSSD) == .secondUnit(with: .milli))
        for kind in [BackloadQuantityKind.restingHeartRate, .heartRate, .respiratoryRate] {
            #expect(HealthKitBackloader.quantityUnit(kind) == HKUnit(from: "count/min"), "\(kind)")
        }
        #expect(HealthKitBackloader.quantityUnit(.vo2Max) == HKUnit(from: "ml/(kg*min)"))
    }

    @Test func quantitySpecBecomesOneVersionedSampleWithItsSyncId() throws {
        let spec = BackloadQuantitySampleSpec(syncId: "floors:2026-09-18", kind: .flightsClimbed, start: t0, end: t0 + 60, value: 12, version: 7)
        let entries = HealthKitBackloader.objectEntries(for: .quantity(spec))
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.syncId == "floors:2026-09-18")
        #expect(entry.version == 7)
        let sample = try #require(entry.object as? HKQuantitySample)
        #expect(sample.quantityType == HKQuantityType(.flightsClimbed))
        #expect(sample.quantity.doubleValue(for: .count()) == 12)
        #expect(sample.metadata?[HKMetadataKeySyncIdentifier] as? String == "floors:2026-09-18")
        #expect(sample.metadata?[HKMetadataKeySyncVersion] as? Int == 7)
    }

    @Test func quantitySpecWithoutVersionFallsBackToTheWriterDefault() throws {
        let spec = BackloadQuantitySampleSpec(syncId: "dist:2026-09-18", kind: .distanceWalkingRunning, start: t0, end: t0 + 60, value: 4_200)
        let entry = try #require(HealthKitBackloader.objectEntries(for: .quantity(spec)).first)
        #expect(entry.version == HealthKitBackloader.syncVersion)
        let sample = try #require(entry.object as? HKQuantitySample)
        #expect(sample.quantity.doubleValue(for: .meter()) == 4_200)
    }

    @Test func workoutSpecDefaultsAndRoundTrip() {
        let minimal = BackloadWorkoutSampleSpec(syncId: "w:1", start: t0, end: t0 + 3600, kind: .running, name: "run", kcal: nil, distanceM: nil, avgHr: nil)
        #expect(minimal.rawType == nil)
        #expect(minimal.indoor == false)
        #expect(minimal.hrSamples.isEmpty)
        #expect(minimal.startEstimated == false)
        #expect(minimal.version == nil)

        let hr = [BackloadWorkoutHRSample(ts: t0 + 10, bpm: 120), BackloadWorkoutHRSample(ts: t0 + 20, bpm: 130)]
        let full = BackloadWorkoutSampleSpec(
            syncId: "w:2", start: t0, end: t0 + 3600, kind: .cycling, name: "katzensee", kcal: 500, distanceM: 20_000, avgHr: 140,
            startEstimated: true, version: 9, rawType: "indoor_cycling", indoor: true, hrSamples: hr)
        #expect(full.rawType == "indoor_cycling")
        #expect(full.indoor == true)
        #expect(full.hrSamples == hr)
        #expect(full == full)
        var copy = full
        copy.indoor = false
        #expect(copy != full)
    }

    @Test func workoutSpecFieldsLandOnTheHKWorkoutAndItsAssociatedSamples() throws {
        let hr = [BackloadWorkoutHRSample(ts: t0 + 10, bpm: 120), BackloadWorkoutHRSample(ts: t0 + 20, bpm: 130)]
        let spec = BackloadWorkoutSampleSpec(
            syncId: "w:2", start: t0, end: t0 + 3600, kind: .running, name: "Monday", kcal: 500, distanceM: 8_000, avgHr: 140,
            version: 9, rawType: "running", indoor: true, hrSamples: hr)
        let entry = try #require(HealthKitBackloader.objectEntries(for: .workout(spec)).first)
        let workout = try #require(entry.object as? HKWorkout)
        #expect(workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool == true)
        #expect(workout.metadata?[HKMetadataKeySyncIdentifier] as? String == "w:2")
        #expect(workout.metadata?[HealthKitBackloader.workoutTitleMetadataKey] as? String == "Monday")
        let ids = entry.associated.compactMap { $0.metadata?[HKMetadataKeySyncIdentifier] as? String }
        #expect(ids.contains("w:2:energy"))
        #expect(ids.contains("w:2:distance"))
        let hrIds = ids.filter { $0.hasPrefix("w:2:hr") }
        #expect(hrIds.count == 2)
        #expect(Set(hrIds) == Set(hr.map { WorkoutHRAttacher.syncId(workout: "w:2", at: $0.ts) }))
        #expect(entry.associated.allSatisfy { $0.metadata?[HKMetadataKeySyncVersion] as? Int == 9 })
    }

    @Test func writeSpecSyncIdFollowsEachCase() {
        let q = BackloadQuantitySampleSpec(syncId: "q", kind: .stepCount, start: t0, end: t0, value: 1)
        let s = BackloadSleepSampleSpec(syncId: "sleep:2026-09-18", inBedStart: t0, inBedEnd: t0, asleepStart: t0, asleepEnd: t0)
        let st = BackloadSleepStagedSampleSpec(baseSyncId: "sleep:2026-09-19", inBedStart: t0, inBedEnd: t0, stages: [])
        let w = BackloadWorkoutSampleSpec(syncId: "w", start: t0, end: t0, kind: .other, name: "", kcal: nil, distanceM: nil, avgHr: nil)
        #expect(BackloadWriteSpec.quantity(q).syncId == "q")
        #expect(BackloadWriteSpec.sleep(s).syncId == "sleep:2026-09-18")
        #expect(BackloadWriteSpec.sleepStaged(st).syncId == "sleep:2026-09-19")
        #expect(BackloadWriteSpec.workout(w).syncId == "w")
        #expect(BackloadWriteSpec.delete(kind: .sleepCategory, syncId: "sleep:2026-09-18:asleep").syncId == "sleep:2026-09-18:asleep")
    }

    @Test func sleepSyncIdsDeriveInBedAndAsleepSuffixes() {
        let s = BackloadSleepSampleSpec(syncId: "sleep:2026-09-18", inBedStart: t0, inBedEnd: t0 + 100, asleepStart: t0, asleepEnd: t0 + 90, version: 3)
        let ids = HealthKitBackloader.objectEntries(for: .sleep(s)).map(\.syncId)
        #expect(ids == ["sleep:2026-09-18:inbed", "sleep:2026-09-18:asleep"])

        let stage = BackloadSleepStageSampleSpec(syncId: "sleep:2026-09-19:st0", stage: .deep, start: t0, end: t0 + 100)
        let st = BackloadSleepStagedSampleSpec(baseSyncId: "sleep:2026-09-19", inBedStart: t0, inBedEnd: t0 + 100, stages: [stage])
        let stagedIds = HealthKitBackloader.objectEntries(for: .sleepStaged(st)).map(\.syncId)
        #expect(stagedIds == ["sleep:2026-09-19:inbed", "sleep:2026-09-19:st0"])
    }
}
#endif

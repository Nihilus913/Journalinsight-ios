#if canImport(HealthKit)
import Foundation
import HealthKit
import Testing
@testable import JIHealthKit

struct WorkoutHRAttacherTests {
    private func ts(_ s: String) -> Date { BackloadDateParsing.timestamp(s)! }

    @Test func selectKeepsSamplesInsideTheWindowInclusiveAndSorted() {
        let all: [BackloadWorkoutHRSample] = [
            .init(ts: ts("2026-06-02T07:15:00+02:00"), bpm: 150),
            .init(ts: ts("2026-06-02T06:59:59+02:00"), bpm: 70),
            .init(ts: ts("2026-06-02T07:00:00+02:00"), bpm: 90),
            .init(ts: ts("2026-06-02T07:30:00+02:00"), bpm: 140),
            .init(ts: ts("2026-06-02T07:30:01+02:00"), bpm: 120),
        ]
        let picked = WorkoutHRAttacher.select(all, start: ts("2026-06-02T07:00:00+02:00"), end: ts("2026-06-02T07:30:00+02:00"))
        #expect(picked.map(\.bpm) == [90, 150, 140])
        #expect(WorkoutHRAttacher.select([], start: ts("2026-06-02T07:00:00+02:00"), end: ts("2026-06-02T07:30:00+02:00")).isEmpty)
    }

    @Test func syncIdIsWorkoutIdPlusZurichHHMMSS() {
        #expect(WorkoutHRAttacher.syncId(workout: "workout:42", at: ts("2026-06-02T07:05:30+02:00")) == "workout:42:hr:070530")
        // winter: UTC+1
        #expect(WorkoutHRAttacher.syncId(workout: "workout:42", at: ts("2026-01-02T23:05:30+01:00")) == "workout:42:hr:230530")
    }

    @Test func samplesAreHeartRateQuantitiesCarryingTheWorkoutVersion() throws {
        let spec = BackloadWorkoutSampleSpec(
            syncId: "workout:42", start: ts("2026-06-02T07:00:00+02:00"), end: ts("2026-06-02T07:30:00+02:00"),
            kind: .running, name: "Base", kcal: nil, distanceM: nil, avgHr: nil, version: 1_789_729_180,
            hrSamples: [.init(ts: ts("2026-06-02T07:05:00+02:00"), bpm: 131), .init(ts: ts("2026-06-02T07:07:00+02:00"), bpm: 144)])
        let samples = WorkoutHRAttacher.samples(for: spec, version: 1_789_729_180)
        #expect(samples.count == 2)
        let first = try #require(samples.first)
        #expect(first.sampleType == HKQuantityType(.heartRate))
        #expect(first.quantity.doubleValue(for: HKUnit(from: "count/min")) == 131)
        #expect(first.startDate == ts("2026-06-02T07:05:00+02:00") && first.endDate == first.startDate)
        #expect(first.metadata?[HKMetadataKeySyncIdentifier] as? String == "workout:42:hr:070500")
        #expect(first.metadata?[HKMetadataKeySyncVersion] as? Int == 1_789_729_180)
        #expect(samples[1].metadata?[HKMetadataKeySyncIdentifier] as? String == "workout:42:hr:070700")
        #expect(WorkoutHRAttacher.samples(for: BackloadWorkoutSampleSpec(syncId: "workout:1", start: spec.start, end: spec.end, kind: .other, name: "x", kcal: nil, distanceM: nil, avgHr: nil), version: 3).isEmpty)
    }
}
#endif
